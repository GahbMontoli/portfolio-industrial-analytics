# Montagem do relatório no Power BI

## Estado atual

O pacote tabular, as consultas Power Query, a consulta DAX canônica e o contrato
de 14 medidas estão prontos. Power BI Desktop não foi localizado no ambiente nas
validações de 30 e 31/10/2026. As consultas ainda precisam ser executadas no
Desktop antes de um projeto PBIP/TMDL ser versionado.

O Power BI Service também exige autenticação com email corporativo ou acadêmico.
Nenhuma conta, tenant, workspace ou licença foi presumida.

| Camada | Estado comprovado |
| --- | --- |
| esquema e dados curados | validado localmente por scripts |
| 14 KPIs | reconciliados fonte↔fato com unidade e tolerância |
| DAX | contratos, referências, formatos e aliases validados estaticamente |
| execução DAX no Desktop | não realizada |
| atualização do modelo semântico | não aplicada |
| PBIP/TMDL | não criado |

## Criar o projeto

1. Abra uma versão atual do Power BI Desktop.
2. Ative/salve como Power BI Project (`.pbip`) usando TMDL.
3. Crie um parâmetro de texto chamado `pDataRoot` apontando para o diretório
   absoluto `data\curated`.
4. Crie uma consulta em branco para cada arquivo em `power-query` e cole o código
   correspondente.
5. Desative carregamento de consultas de staging, caso sejam adicionadas.
6. Crie relacionamentos um-para-muitos das dimensões para os fatos.
7. Marque `DimDate[date]` como tabela de datas e ordene nomes de mês/dia pelas
   respectivas colunas numéricas.
8. Importe o tema `powerbi\theme\industrial-analytics.json`.
9. Execute `scripts\Test-PortfolioBiKpis.ps1` e
   `scripts\Test-PortfolioBiMeasures.ps1` e confira os dois relatórios JSON.
10. Abra a DAX Query View e execute
    `powerbi\measures\IndustrialMeasures.dax`; as medidas em `DEFINE MEASURE`
    permanecem limitadas à consulta nesse momento.
11. Compare os 14 aliases retornados com `kpi-reconciliation.json`.
12. Somente depois da comparação, use `Update model with changes` e aplique
    formatos e pastas de `measure-contracts.json`.
13. Reconcilie no Power BI pelo menos uma medida de cada fato com o mesmo valor
    registrado pelo script, preservando filtros, unidade e granularidade.
14. Salve, feche, reabra e execute atualização completa antes do commit.

## Relacionamentos mínimos do MVP

- `DimProject[project_id]` 1:* `FactWorkOrder[project_id]`;
- `DimProject[project_id]` 1:* `FactH3Observation[project_id]`;
- `DimProject[project_id]` 1:* `FactH3Experiment[project_id]`;
- `DimProject[project_id]` 1:* `FactFaultStudy[project_id]`;
- `DimAsset[asset_id]` 1:* `FactWorkOrder[asset_id]`;
- `DimDate[date_key]` 1:* `FactH3Observation[observed_date_key]`;
- `DimDate[date_key]` 1:* `FactH3Experiment[observed_date_key]`;
- `DimDate[date_key]` 1:* `FactFaultStudy[observed_date_key]`;
- `DimDate[date_key]` 1:* `FactWorkOrder[opened_date_key]` (ativa);
- `DimDate[date_key]` 1:* `FactWorkOrder[closed_date_key]` (inativa);
- `DimEvidence[evidence_key]` 1:* cada uma das quatro tabelas fato;
- `DimSource[source_key]` 1:* cada uma das quatro tabelas fato;
- `FactWorkOrder[work_order_id]` 1:* `BridgeWorkOrderCheck[work_order_id]`;
- `FactWorkOrder[work_order_id]` 1:* `BridgeWorkOrderPart[work_order_id]`.

Use direção única da dimensão para o fato. Não conecte fatos diretamente. Não
crie outra relação ativa entre `DimDate` e
`FactWorkOrder[observed_date_key]`: essa coluna repete a data de abertura para
cumprir o contrato comum. As chaves de evidência e fonte presentes nas pontes
são de auditoria; relacioná-las ativamente junto ao caminho via ordem criaria
ambiguidade.

O timestamp de `FactH3Experiment` usa a última gravação UTC do arquivo como
proxy de disponibilidade do lote, não o instante real de cada replicação. Exiba
essa limitação quando o relatório usar esse campo temporal.

## Atualização e publicação

- arquivo local no Desktop: atualização manual;
- arquivo local no Power BI Service: gateway obrigatório;
- atualização automática de página: exige DirectQuery ou modo compatível;
- `Publish to web`: proibido para dados não destinados explicitamente ao público;
- workspace e RLS: definir antes de qualquer compartilhamento.

## Critérios de verificação visual

- unidade presente em todo KPI;
- classe de evidência visível;
- data/hora de atualização visível;
- filtros sincronizados entre páginas relevantes;
- página móvel legível;
- contraste e texto alternativo nos visuais;
- estado vazio explicado;
- nenhum visual sugere causalidade a partir de associação ou simulação.
