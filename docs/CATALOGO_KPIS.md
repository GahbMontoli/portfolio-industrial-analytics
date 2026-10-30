# Catálogo inicial de KPIs e medidas

As fórmulas são especificações iniciais. Devem ser reconciliadas contra os dados
de origem antes de entrar no relatório publicado.

## Manutenção

| KPI | Definição | Limite |
| --- | --- | --- |
| Ordens abertas | contagem de OS com status aberto no corte | depende da qualidade do status |
| Backlog por idade | OS abertas agrupadas por dias desde abertura | não mede esforço em horas |
| MTTR observado | média da duração de OS concluídas | não representa tempo ativo de reparo sem apontamento |
| Recorrência | OS com mesmo ativo/código dentro da janela | similaridade não confirma mesma causa |
| Completude | OS concluídas com causa, resolução e encerramento | mede registro, não qualidade técnica da solução |

Exemplos DAX:

```DAX
Ordens Abertas =
CALCULATE(
    COUNTROWS(FactWorkOrder),
    FactWorkOrder[is_closed] = FALSE()
)

MTTR Observado (h) =
AVERAGEX(
    FILTER(FactWorkOrder, FactWorkOrder[is_closed] = TRUE()),
    DIVIDE(
        DATEDIFF(
            FactWorkOrder[opened_at_utc],
            FactWorkOrder[closed_at_utc],
            MINUTE
        ),
        60.0
    )
)

Completude de Encerramento (%) =
DIVIDE(
    CALCULATE(
        COUNTROWS(FactWorkOrder),
        FactWorkOrder[is_closed] = TRUE(),
        FactWorkOrder[has_cause] = TRUE(),
        FactWorkOrder[has_resolution] = TRUE()
    ),
    CALCULATE(
        COUNTROWS(FactWorkOrder),
        FactWorkOrder[is_closed] = TRUE()
    )
)
```

## H3

| KPI | Definição | Limite |
| --- | --- | --- |
| Horas H3 | soma do intervalo quando risco >= elevado | limiar experimental |
| Eventos H3 | sequências contínuas de risco >= elevado | depende da frequência de coleta |
| Margem mínima | menor superfície menos ponto de orvalho | simulação não prova condensação real |
| Cobertura | slots válidos / slots esperados | dados brutos podem não estar consistidos |
| Diferença pareada | referência menos intervenção por réplica | efeito apenas dentro do modelo |

```DAX
Horas H3 =
SUMX(
    FILTER(FactH3Observation, FactH3Observation[risk_rank] >= 2),
    FactH3Observation[interval_hours]
)

Cobertura H3 (%) =
DIVIDE(
    SUM(FactDataQuality[accepted_rows]),
    SUM(FactDataQuality[evaluated_rows])
)
```

## Simulador

| KPI | Definição | Limite |
| --- | --- | --- |
| Taxa de expectativa | cenários com resposta esperada / executados | valida modelo, não hardware |
| Divergência comando/estado | passos com valor bruto diferente do efetivo | forçamento/falha pode ser intencional |
| Tags degradadas | tags com qualidade diferente de boa | fotografia do instante |
| Passos perdidos | passos não executados pelo relógio | depende de hardware e carga |
| Desvio de sensor | máximo físico menos indicado | valor sintético |

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
```

## Qualidade e governança

- percentual de ausentes;
- duplicidades por chave natural;
- lotes rejeitados;
- atraso `ingested_at_utc - observed_at_utc`;
- fontes sem hash ou versão;
- última atualização por fato;
- quantidade de linhas por classe de evidência.

Nunca calcular média de médias sem o peso original. Percentuais devem preservar
numerador e denominador na mesma granularidade e no mesmo contexto de filtro.
