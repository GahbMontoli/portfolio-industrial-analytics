# Plano mestre de evolução do portfólio industrial e Power BI

Data-base da pesquisa: 30/10/2026.

## 1. Resultado pretendido

Transformar três protótipos independentes em uma suíte demonstrável de engenharia
industrial orientada por dados:

```text
sensores/simulações/CMMS
          |
          v
 dados brutos imutáveis
          |
          v
 validação + contrato + qualidade
          |
          v
 modelo dimensional / banco analítico
          |
          v
 Power BI + decisões rastreáveis
```

O portfólio deve provar cinco competências ao mesmo tempo:

- conhecimento de manutenção, confiabilidade e processos;
- programação e testes automatizados;
- integração industrial e IT/OT;
- engenharia, qualidade e governança de dados;
- análise no Power BI com Power Query, DAX e segurança.

## 2. Evidência de mercado usada para priorização

Uma amostra atual de vagas brasileiras mostra a convergência entre os domínios.
Uma posição de Smart Manufacturing da Volkswagen Caminhões e Ônibus pede Power
BI, Power Query, DAX, SQL, APIs, ETL/ELT, Python, PLC, HMI/SCADA, OPC UA, MQTT,
integração IT/OT, documentação, testes e cibersegurança. Uma posição de
monitoramento de ativos da Auren combina manutenção preditiva, SCADA/CMS,
qualidade de dados e Power Platform. Outras vagas industriais consultadas pedem
Power BI, SQL, Python, ETL e integração de dados operacionais.

Isso não é uma estatística de todo o mercado. É evidência observacional atual
para orientar o portfólio, complementada pelo Future of Jobs Report 2025, que
prioriza AI/big data, redes/cibersegurança e alfabetização tecnológica.

## 3. Decisão arquitetural

### 3.1 Camadas

- **Bronze/raw:** arquivo exatamente como obtido, com origem, horário, hash,
  versão do esquema e classe de evidência.
- **Silver/validated:** tipos corrigidos, chaves estáveis, fuso normalizado,
  duplicidades e valores inválidos marcados; nenhuma correção silenciosa.
- **Gold/semantic:** fatos e dimensões no grão declarado, medidas explícitas e
  nomes compreensíveis para o negócio.

### 3.2 Classes de evidência obrigatórias

| Código | Significado | Pode provar |
| --- | --- | --- |
| `synthetic` | Simulação ou dado fabricado para teste | Comportamento do software/modelo |
| `official_raw` | Dado oficial bruto/não consistido | Condição registrada pela fonte, com suas limitações |
| `lab_observed` | Medição controlada de bancada | Resultado no arranjo e protocolo ensaiados |
| `field_observed` | Medição real de campo | Associação observada no contexto medido |
| `derived` | Transformação calculada | Resultado do método declarado |

Nenhuma medida deve agregar classes incompatíveis sem filtro visível.

### 3.3 Estratégia Power BI

1. **MVP econômico:** Power BI Desktop + Import de pasta com arquivos
   padronizados. Bom para portfólio, mas não é tempo real.
2. **Piloto profissional:** PostgreSQL ou SQL Server com tabelas históricas,
   atualização incremental e gateway quando a origem estiver local.
3. **Monitoramento próximo do tempo real:** DirectQuery e atualização automática
   de página, respeitando capacidade, desempenho e segurança.
4. **Streaming futuro:** Fabric Real-Time Intelligence/Eventstream. Não construir
   nova arquitetura sobre os modelos legados de streaming do Power BI, cuja
   criação será descontinuada após 31/10/2027.

O projeto Power BI deve usar PBIP/TMDL para revisão em Git. Arquivos `.pbix`
binários podem continuar como artefatos de demonstração, mas não serão a única
fonte do relatório.

## 4. Evolução por sistema

### 4.1 H3 Climate Reliability Lab

**Estado útil atual:** série sintética temporal, experimento pareado, estatística,
dados INMET externos, proveniência e separação explícita de evidências.

**Lacunas prioritárias:**

1. Adicionar `run_id`, `source_id`, intervalo em minutos e versão do esquema a
   cada exportação.
2. Criar tabelas BI separadas para observações, execuções, intervenções,
   estatísticas e qualidade de dados.
3. Descontinuar gradualmente o dashboard HTML depois de alcançar paridade no
   Power BI; manter CSV/JSON como saídas auditáveis.
4. Criar página H3 com envelope real versus sintético, ausências, exposição,
   eventos, margem para ponto de orvalho e intervalo de confiança.
5. Recalibrar o gerador somente com protocolo definido antes da análise e
   conservar versão anterior para comparação.
6. Criar importador de sensor de bancada com incerteza, calibração, unidade,
   posição, frequência e cadeia de custódia.
7. Executar bancada desenergizada; depois piloto de campo somente leitura.
8. Só modelar relação com falhas após haver vínculo temporal, ativos, carga,
   idade, intervenção e confundidores suficientes.

**Diferencial de mercado:** engenharia ambiental aplicada à confiabilidade,
estatística responsável e rastreabilidade de dados oficiais.

### 4.2 Simulador Industrial 3D

**Estado útil atual:** cena autoral, tags, Modbus TCP, eventos, qualidade,
forçamento, injeção de falhas, CSV/JSON e testes.

**Lacunas prioritárias:**

1. Exportar telemetria temporal, não apenas instantâneo e eventos: `run_id`,
   `tick`, timestamp UTC, tag, valor bruto, valor efetivo, qualidade e falha.
2. Versionar o contrato de eventos e de telemetria.
3. Criar páginas BI de execução, alarmes, divergência comando/estado, passos
   perdidos, latência e comparação de cenários.
4. Concluir o ensaio externo OpenPLC de 60 minutos antes de declarar
   interoperabilidade comprovada com esse runtime.
5. Implementar um adaptador OPC UA autoral usando especificações públicas e
   testes de conformidade do próprio projeto.
6. Adicionar publicação MQTT somente leitura para telemetria; comandos devem ter
   autenticação, autorização, auditoria e modo seguro.
7. Expandir biblioteca de componentes por pacotes assináveis e validados.
8. Criar cenários de motor, transportador, bomba, tanque, sensor analógico,
   intertravamento e sequência de partida.
9. Adicionar análise de desempenho e orçamento de tempo por sistema.
10. Manter implementação clean-room: sem código, assets, formatos ou identidade
    proprietária de produtos usados como referência funcional.

**Diferencial de mercado:** digital twin verificável, integração IT/OT e
diagnóstico auditável em vez de apenas uma animação 3D.

### 4.3 Copiloto de Confiabilidade

**Estado útil atual:** ativos, ordens de serviço, validador de dados, triagem
explicável e conector CMMS simulado.

**Lacunas prioritárias:**

1. Exportar fatos de ordens, ativos, verificações e peças em tabelas separadas.
2. Adicionar códigos controlados de modo, causa, mecanismo, ação e consequência,
   inspirados na estrutura de dados da ISO 14224 sem alegar conformidade formal.
3. Criar métricas de backlog, recorrência, MTTR, qualidade do encerramento,
   reincidência por ativo/modelo e idade da ordem.
4. Implementar conector real somente leitura para API CMMS, com paginação,
   retries, limites, autenticação segura e log de auditoria.
5. Bloquear qualquer recomendação quando dados mínimos estiverem ausentes.
6. Registrar por que cada caso foi considerado semelhante; manter decisão humana.
7. Criar rascunho de ordem somente após aprovação explícita, nunca gravação
   automática em CMMS produtivo.
8. Adicionar perfis, RLS no modelo Power BI e segregação por local/unidade.
9. Construir conjunto sintético versionado para avaliar precisão, cobertura e
   falsos positivos da triagem.
10. Só avançar para modelos preditivos quando houver dados reais suficientes,
    rótulos confiáveis e validação temporal fora da amostra.

**Diferencial de mercado:** copiloto com governança e explicabilidade, não um
chatbot que inventa diagnóstico.

## 5. Modelo compartilhado

O modelo dimensional comum está em `MODELO_DIMENSIONAL.md`. As chaves que unem os
sistemas serão:

- `project_id`;
- `run_id`;
- `asset_id`;
- `location_id`;
- `scenario_id`;
- `source_id`;
- `observed_at_utc`;
- `evidence_class`;
- `quality_status`;
- `schema_version`.

O H3 poderá se ligar a ativos do CMMS somente por uma tabela de associação
versionada e aprovada. O simulador poderá gerar ordens sintéticas, mas elas devem
permanecer marcadas como `synthetic` e nunca entrar no backlog real.

## 6. Páginas do relatório Power BI

### Página 1 — Visão executiva

- projetos, execuções e fontes ativas;
- qualidade, atualização e classe de evidência;
- principais riscos e exceções;
- navegação para páginas técnicas.

### Página 2 — Manutenção e confiabilidade

- backlog por criticidade e idade;
- MTTR e recorrência com filtros de ativo/local/modelo;
- Pareto de códigos de falha e causas registradas;
- completude de encerramento e ordens bloqueadas por qualidade.

### Página 3 — H3 e clima

- temperatura, RH, ponto de orvalho e margem;
- horas e eventos por faixa experimental;
- real externo versus sintético externo;
- ausências, cobertura e proveniência INMET;
- resultados pareados com IC95% e aviso de evidência sintética.

### Página 4 — Simulação e falhas

- execuções e cenário;
- divergência comando/estado;
- tags com qualidade ruim, forçamento ou falha;
- tempo até alvo, volume físico versus indicado e passos perdidos;
- timeline de eventos e comparação nominal/falhas.

### Página 5 — Qualidade e proveniência

- linhas aceitas, rejeitadas, ausentes e duplicadas;
- hash, versão, origem, atualização e responsável;
- frescor e atraso de ingestão;
- testes e critérios de aceite por conjunto.

### Página 6 — Pesquisa e hipóteses

- hipótese, método, população, variável, resultado e limitação;
- fonte acadêmica/oficial associada;
- status: proposta, simulada, bancada, campo, reproduzida;
- resultados nulos ou contrários preservados.

## 7. Roadmap de execução

### Ciclo 1 — Fundação (semanas 1–2)

- aprovar contrato comum v1;
- adicionar `run_id`, versão e classe de evidência às exportações;
- criar testes de esquema e qualidade;
- definir parâmetros `pDataRoot`, fuso e período no Power Query;
- montar DimDate, DimProject, DimEvidence e DimSource.

### Ciclo 2 — MVP Power BI (semanas 3–4)

- criar projeto PBIP/TMDL;
- importar H3, cenário de falhas e CMMS sintético;
- implementar medidas do catálogo;
- validar uma amostra de cada medida contra a fonte;
- criar as cinco páginas principais e versão móvel.

### Ciclo 3 — Dados operacionais simulados (semanas 5–7)

- telemetria temporal do simulador;
- exportador tabular do Copiloto;
- tabela de qualidade e proveniência;
- testes de volume, duplicidade, fuso e chaves;
- documentação e vídeo técnico reproduzível.

### Ciclo 4 — Banco e atualização (semanas 8–10)

- PostgreSQL/SQL Server em ambiente local de laboratório;
- carga idempotente e incremental;
- DirectQuery apenas para fatos que exigem baixa latência;
- gateway e atualização agendada em workspace restrito;
- medir latência, carga e custo antes de chamar de tempo real.

### Ciclo 5 — Integração industrial (semanas 11–16)

- OpenPLC externo;
- OPC UA e MQTT somente leitura;
- observabilidade e ameaça/cibersegurança;
- bancada H3 instrumentada;
- conector CMMS somente leitura com dados anonimizados ou sintéticos.

### Ciclo 6 — Evidência profissional (meses 5–6)

- estudo de caso completo por sistema;
- artigo técnico com método e limitações;
- relatório Power BI com RLS;
- release instalável e demonstração gravada;
- matriz de competências versus evidências do GitHub.

## 8. Critérios de pronto

Uma entrega só pode ser apresentada como concluída quando:

- contrato, grão, unidade e fuso estiverem documentados;
- fonte e classe de evidência estiverem visíveis;
- teste automatizado validar esquema e regra crítica;
- medida Power BI reconciliar com uma amostra da fonte;
- filtros não alterarem indevidamente o denominador;
- resultado nulo/contrário não for ocultado;
- relatório indicar data/hora de atualização;
- dados pessoais, empresariais e credenciais estiverem ausentes;
- README explicar execução, limitações e reprodução.

## 9. Competências a demonstrar no GitHub

| Competência | Evidência concreta |
| --- | --- |
| Power BI | PBIP/TMDL, Power Query, DAX, RLS, relatório móvel |
| SQL | esquema estrela, views, carga incremental, testes de qualidade |
| Programação | C#/.NET testado; Python apenas onde agregar análise justificável |
| Automação | Modbus TCP, PLC externo, OPC UA, MQTT e contratos versionados |
| Manutenção | backlog, MTTR, recorrência, criticidade e qualidade de OS |
| Processos | KPIs, rastreabilidade, bloqueios, critérios de aceite |
| Estatística | IC, amostra, incerteza, validação temporal e limites causais |
| Segurança | mínimo privilégio, segredos fora do código, auditoria e RLS |
| Pesquisa | DOI/URL, data de acesso, método, limitações e reprodutibilidade |

## 10. Próximo avanço recomendado

Começar pelo contrato tabular v1 e pelo exportador do Copiloto de Confiabilidade.
Ele é pequeno, já possui dados sintéticos relacionais e permite demonstrar
rapidamente Power Query, esquema estrela, DAX, qualidade e manutenção. Em
paralelo, conservar H3 e Simulador como fontes prontas para as páginas seguintes.
