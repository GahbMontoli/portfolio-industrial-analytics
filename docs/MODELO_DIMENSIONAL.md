# Modelo dimensional v1

O desenho segue esquema estrela: dimensões filtram e agrupam; fatos mantêm um
grão consistente e são resumidos por medidas explícitas.

## Dimensões conformadas

| Tabela | Chave | Conteúdo |
| --- | --- | --- |
| `DimDate` | `date_key` | data, ano, mês, semana, dia útil |
| `DimTime` | `time_key` | hora, minuto e faixa operacional |
| `DimProject` | `project_key` | H3, Simulator ou CMMS |
| `DimAsset` | `asset_key` | tag, categoria, modelo, criticidade |
| `DimLocation` | `location_key` | unidade, área, linha e célula |
| `DimScenario` | `scenario_key` | cenário, intervenção e versão |
| `DimFailureMode` | `failure_mode_key` | código, modo, causa e mecanismo |
| `DimEvidence` | `evidence_key` | classe, qualidade e limite interpretativo |
| `DimSource` | `source_key` | sistema, URI, hash, licença e versão |

Dimensões não disponíveis em uma fonte usam uma linha `Unknown`, nunca uma chave
vazia que rompa o relacionamento.

## Fatos

### `FactH3Observation`

Grão: uma observação por `run_id`, timestamp e cenário.

Medidas-base: temperaturas, umidades, ponto de orvalho, margem, intervalo em
horas, faixa de risco, porta e HVAC.

### `FactH3Experiment`

Grão: uma replicação por intervenção.

Medidas-base: exposição referência/intervenção, eventos, margem mínima, diferença
pareada e semente.

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
- dimensões de data de abertura e encerramento usam papéis distintos ou relações
  inativas acionadas por medida;
- todos os timestamps persistidos em UTC, com conversão local apenas na camada
  de apresentação.

## Particionamento e atualização

- `FactH3Observation`, `FactSimulationEvent` e telemetria: particionar por data;
- ordens: atualizar janela recente e manter histórico fechado;
- dimensões: atualização completa enquanto pequenas;
- lotes devem ser idempotentes por `source_hash + schema_version + run_id`;
- falha de qualidade bloqueia promoção de Silver para Gold, sem apagar Bronze.
