# Catálogo de KPIs reconciliados

As medidas abaixo usam somente colunas existentes no pacote curado. Antes de
serem levadas ao relatório, suas unidades, filtros, numeradores e denominadores
são recalculados diretamente nas fontes registradas e comparados aos quatro
fatos por `scripts\Test-PortfolioBiKpis.ps1`.

O pacote atual é inteiramente `synthetic`. A reconciliação prova o contrato e a
aritmética do software; não demonstra desempenho de uma planta, efeito causal,
confiabilidade de hardware ou resultado de manutenção em campo.

## Manutenção

| KPI | Cálculo e unidade | Filtro | Limite |
| --- | --- | --- | --- |
| Ordens abertas | contagem de OS | `is_closed = false` | não representa backlog real |
| Ordens encerradas | contagem de OS | `is_closed = true` | não comprova produtividade |
| MTTR observado | média de `duration_hours`, em horas | OS encerradas | mede tempo calendário, não tempo ativo de reparo |
| Completude de encerramento | OS encerradas com causa, resolução e data / OS encerradas, em razão | OS encerradas | mede preenchimento, não qualidade da solução |
| Checks vinculados | contagem de linhas da ponte | sem filtro | não comprova execução do check em campo |
| Peças vinculadas | contagem de linhas da ponte | sem filtro | não representa consumo real de estoque |

Especificação DAX compatível com as colunas atuais:

```DAX
Ordens Abertas =
CALCULATE(
    COUNTROWS(FactWorkOrder),
    FactWorkOrder[is_closed] = FALSE()
)

Ordens Encerradas =
CALCULATE(
    COUNTROWS(FactWorkOrder),
    FactWorkOrder[is_closed] = TRUE()
)

MTTR Observado (h) =
CALCULATE(
    AVERAGE(FactWorkOrder[duration_hours]),
    FactWorkOrder[is_closed] = TRUE()
)

Completude de Encerramento (%) =
VAR Encerradas =
    CALCULATE(
        COUNTROWS(FactWorkOrder),
        FactWorkOrder[is_closed] = TRUE()
    )
VAR Completas =
    CALCULATE(
        COUNTROWS(FactWorkOrder),
        FactWorkOrder[is_closed] = TRUE(),
        FactWorkOrder[has_cause] = TRUE(),
        FactWorkOrder[has_resolution] = TRUE(),
        NOT ISBLANK(FactWorkOrder[closed_at_utc])
    )
RETURN
    DIVIDE(Completas, Encerradas)
```

`Backlog por idade` permanece pendente até existir uma data de corte/snapshot
versionada. `Recorrência` permanece pendente até a janela e a regra de
agrupamento serem formalizadas; similaridade não confirma a mesma causa.

## H3: observações sintéticas

| KPI | Cálculo e unidade | Filtro | Limite |
| --- | --- | --- | --- |
| Horas em risco H3 | soma de `interval_minutes` / 60, em horas | `risk_level` em `High` ou `Critical` | limiar experimental |
| Margem mínima H3 | mínimo de `dew_point_margin_c`, em °C | contexto selecionado | não prova condensação real |

```DAX
Horas em Risco H3 =
SUMX(
    FILTER(
        FactH3Observation,
        FactH3Observation[risk_level] IN {"High", "Critical"}
    ),
    DIVIDE(FactH3Observation[interval_minutes], 60.0)
)

Margem Mínima H3 (°C) =
MIN(FactH3Observation[dew_point_margin_c])
```

`Eventos H3` contínuos não são calculados ainda porque o fato não possui
`event_id` ou segmentação de episódios. `Cobertura H3` também permanece no
backlog porque `FactDataQuality` e os slots esperados ainda não foram
materializados. Nenhuma fórmula deve referenciar essas estruturas antes disso.

## H3: experimento pareado sintético

| KPI | Cálculo e unidade | Grão | Limite |
| --- | --- | --- | --- |
| Diferença pareada média de exposição | média de `baseline_exposure_hours - intervention_exposure_hours`, em h/réplica | réplica e intervenção | efeito somente dentro do modelo |
| Eventos de alto risco evitados | soma de `baseline_high_risk_events - intervention_high_risk_events`, em contagem | réplica e intervenção | depende da regra experimental |
| Ganho médio de margem mínima | média de `intervention_minimum_margin_c - baseline_minimum_margin_c`, em °C/réplica | réplica e intervenção | não é evidência de campo |

Valores negativos nas diferenças são permitidos: eles representam uma
intervenção simulada pior que a referência e não devem ser apagados nem
forçados a zero.

## Simulador Industrial 3D

| KPI | Cálculo e unidade | Filtro | Limite |
| --- | --- | --- | --- |
| Taxa de expectativa | cenários com `expectation_met = true` / cenários executados, em razão | contexto selecionado | valida o software, não hardware ou PLC real |
| Passos de divergência | soma de `valve_command_divergence_steps`, em passos | contexto selecionado | falha/forçamento pode ser intencional |
| Desvio máximo de sensor | máximo de `maximum_sensor_deviation_liters`, em L | contexto selecionado | valor sintético |

```DAX
Taxa de Expectativa (%) =
DIVIDE(
    CALCULATE(
        COUNTROWS(FactFaultStudy),
        FactFaultStudy[expectation_met] = TRUE()
    ),
    COUNTROWS(FactFaultStudy)
)

Passos de Divergência =
SUM(FactFaultStudy[valve_command_divergence_steps])

Desvio Máximo de Sensor (L) =
MAX(FactFaultStudy[maximum_sensor_deviation_liters])
```

`Tags degradadas` e `Passos perdidos` dependem do fato de telemetria temporal,
que ainda não integra este pacote.

## Snapshot reproduzido em 30/10/2026

| Métrica sintética | Fato curado | Fonte registrada |
| --- | ---: | ---: |
| Ordens abertas / encerradas | 3 / 9 | 3 / 9 |
| MTTR observado | 3,194333 h | 3,194444 h |
| Completude | 9/9 = 100% | 9/9 = 100% |
| Checks / peças | 33 / 4 | 33 / 4 |
| Horas em risco H3 | 9,666667 h | 9,666667 h |
| Margem mínima H3 | 0,736 °C | 0,736 °C |
| Diferença média de exposição | 6,883333 h/réplica | 6,883333 h/réplica |
| Eventos de alto risco evitados | 819 | 819 |
| Ganho médio de margem mínima | 1,273467 °C/réplica | 1,273467 °C/réplica |
| Taxa de expectativa | 5/5 = 100% | 5/5 = 100% |
| Passos de divergência | 599 | 599 |
| Desvio máximo de sensor | 1,0 L | 1,0 L |

A pequena diferença de MTTR decorre do arredondamento de cada duração para três
casas no fato. A tolerância aceita é `0,001 h`; a fonte permanece preservada e
é recalculada pelos timestamps.

## Executar a reconciliação

```powershell
.\scripts\New-PortfolioBiDataset.ps1
.\scripts\Test-PortfolioBiDataset.ps1
.\scripts\Test-PortfolioBiKpis.ps1
```

O último comando gera `data\curated\kpi-reconciliation.json` com os hashes das
fontes, valor do fato, valor recalculado na fonte, diferença, tolerância,
unidade, grão, filtro, classe de evidência e limite interpretativo de cada KPI.

As fórmulas DAX deste documento continuam sendo especificações textuais. A
sintaxe e o comportamento no modelo semântico só poderão ser declarados
validados após execução no Power BI Desktop.
