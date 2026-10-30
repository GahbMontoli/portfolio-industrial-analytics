# Modelo dimensional v1

O desenho segue esquema estrela: dimensões filtram e agrupam; fatos mantêm um
grão consistente e são resumidos por medidas explícitas.

## Dimensões conformadas implementadas

| Tabela | Grão e chave | Conteúdo |
| --- | --- | --- |
| `DimDate` | uma data UTC por `date_key` (`yyyyMMdd`) | ano, trimestre, mês, semana ISO, dia e indicador de fim de semana |
| `DimProject` | um projeto por `project_id` | H3, Simulador Industrial 3D ou Copiloto de Confiabilidade |
| `DimAsset` | um ativo sintético por `asset_id` | tag, categoria, modelo, localização e criticidade |
| `DimEvidence` | uma combinação classe/qualidade por `evidence_key` | 20 combinações permitidas, limites interpretativos e membro `Unknown` |
| `DimSource` | uma versão de fonte por `source_key` | projeto, identificador lógico, URI, localizador portável, hash e versão |

`DimEvidence` combina as cinco classes `synthetic`, `official_raw`,
`lab_observed`, `field_observed` e `derived` com os quatro estados `valid`,
`warning`, `rejected` e `raw_unvalidated`. Catalogar os 20 estados possíveis
não significa aceitar linhas rejeitadas na camada curada.

`DimSource[source_key]` é formada por
`project_id|source_id|sha256`. Assim, uma alteração de conteúdo cria uma nova
versão de proveniência em vez de substituir silenciosamente a origem anterior.
O localizador é relativo ao workspace e usa barras portáveis; nenhum caminho
absoluto do computador integra a dimensão publicada.

`DimDate` é a exceção deliberada à regra de membro desconhecido: uma tabela de
datas do Power BI deve ter valores únicos, não nulos e contíguos, cobrindo anos
completos. Por isso ela não possui linha `Unknown`; datas de encerramento ainda
ausentes permanecem nulas no fato. Outras dimensões sem correspondência podem
usar um membro `Unknown` explícito, nunca uma chave vazia que rompa o
relacionamento.

`DimTime`, `DimLocation`, `DimScenario` e `DimFailureMode` permanecem no backlog
e só serão materializadas quando houver grão e dados-fonte suficientes.

## Fatos

### `FactH3Observation`

Grão: uma observação por `run_id`, timestamp e cenário.

Medidas-base: temperaturas, umidades, ponto de orvalho, margem, intervalo em
horas, faixa de risco, porta e HVAC.

### `FactH3Experiment`

Grão: uma replicação por intervenção.

Medidas-base: exposição referência/intervenção, eventos, margem mínima, diferença
pareada e semente.

Limitação temporal: no contrato atual, `observed_at_utc` é a data de última
gravação UTC do arquivo de resultados, usada como proxy de disponibilidade do
lote. Ela não representa o instante de execução de cada replicação e aparece em
`observed_time_basis` como `source_file_last_write_utc_proxy`.

### `FactSimulationEvent`

Grão: um evento por execução e sequência monotônica.

Medidas-base: tick, categoria, tag e timestamp.

### `FactSimulationTagSnapshot`

Grão: uma tag por execução e instante de coleta.

Medidas-base: valor bruto/efetivo, qualidade, forçamento, falha e último tick.

### `FactFaultStudy`

Grão: um resultado por execução e cenário de falha.

Medidas-base: expectativa, tempo até alvo, volumes, desvio de sensor e passos de
divergência da válvula.

### `FactWorkOrder`

Grão: uma ordem de serviço.

Medidas-base: abertura, encerramento, status, prioridade, idade e duração.

`opened_date_key` representa a data de abertura e `closed_date_key` a data de
encerramento, quando existente. A coluna comum `observed_date_key` também
representa a abertura e é preservada para manter o contrato analítico comum.

As tabelas `BridgeWorkOrderCheck` e `BridgeWorkOrderPart` preservam listas
multivaloradas por ordem e ordinal, sem concatenar itens em uma única célula.

### `FactDataQuality`

Grão: uma regra de qualidade por lote/fonte.

Medidas-base: linhas avaliadas, aprovadas, rejeitadas, ausentes, duplicadas e
percentual de conformidade.

## Relacionamentos

- relações um-para-muitos, direção de filtro da dimensão para o fato;
- evitar muitos-para-muitos direto;
- fatos não se relacionam diretamente entre si;
- associações de ativo externo usam tabela ponte versionada;
- `DimDate[date_key]` filtra ativamente os três fatos de simulação/experimento
  por `observed_date_key`;
- para ordens, a relação ativa usa `opened_date_key`; a relação com
  `closed_date_key` fica inativa e é acionada somente por medidas específicas;
- `FactWorkOrder[observed_date_key]` replica a data de abertura para auditoria do
  contrato e não deve criar uma segunda relação ativa com `DimDate`;
- `DimEvidence` e `DimSource` filtram os quatro fatos por suas chaves técnicas;
- as pontes CMMS preservam essas mesmas chaves para rastreabilidade, mas não
  devem criar rotas de filtro ativas ambíguas além de `FactWorkOrder`;
- todos os timestamps persistidos em UTC, com conversão local apenas na camada
  de apresentação.

## Particionamento e atualização

- `FactH3Observation`, `FactSimulationEvent` e telemetria: particionar por data;
- ordens: atualizar janela recente e manter histórico fechado;
- dimensões: atualização completa enquanto pequenas;
- lotes devem ser idempotentes por `source_hash + schema_version + run_id`;
- falha de qualidade bloqueia promoção de Silver para Gold, sem apagar Bronze.
