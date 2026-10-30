# Montagem do relatório no Power BI

## Estado atual

O pacote tabular e as consultas Power Query estão prontos. Power BI Desktop não
foi localizado no ambiente durante a validação de 30/10/2026. As consultas M
ainda precisam ser aplicadas e verificadas no Power BI Desktop antes de um
projeto PBIP/TMDL ser versionado.

O Power BI Service também exige autenticação com email corporativo ou acadêmico.
Nenhuma conta, tenant, workspace ou licença foi presumida.

## Criar o projeto

1. Abra uma versão atual do Power BI Desktop.
2. Ative/salve como Power BI Project (`.pbip`) usando TMDL.
3. Crie um parâmetro de texto chamado `pDataRoot` apontando para o diretório
   absoluto `data\curated`.
4. Crie uma consulta em branco para cada arquivo em `power-query` e cole o código
   correspondente.
5. Desative carregamento de consultas de staging, caso sejam adicionadas.
6. Crie relacionamentos um-para-muitos das dimensões para os fatos.
7. Importe o tema `powerbi\theme\industrial-analytics.json`.
8. Adicione as medidas descritas em `CATALOGO_KPIS.md`.
9. Reconcilie pelo menos uma medida de cada fato com o CSV de origem.
10. Salve, feche, reabra e execute atualização completa antes do commit.

## Relacionamentos mínimos do MVP

- `DimProject[project_id]` 1:* `FactWorkOrder[project_id]`;
- `DimProject[project_id]` 1:* `FactH3Observation[project_id]`;
- `DimProject[project_id]` 1:* `FactH3Experiment[project_id]`;
- `DimProject[project_id]` 1:* `FactFaultStudy[project_id]`;
- `DimAsset[asset_id]` 1:* `FactWorkOrder[asset_id]`.
- `FactWorkOrder[work_order_id]` 1:* `BridgeWorkOrderCheck[work_order_id]`;
- `FactWorkOrder[work_order_id]` 1:* `BridgeWorkOrderPart[work_order_id]`.

Use direção única da dimensão para o fato. Não conecte fatos diretamente.

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
