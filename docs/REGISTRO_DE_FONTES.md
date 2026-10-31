# Registro inicial de fontes

Consultas realizadas em 30 e 31/10/2026.

| Fonte | Tipo | Uso no plano | Limitação |
| --- | --- | --- | --- |
| [Microsoft PL-300 study guide](https://learn.microsoft.com/en-us/certifications/resources/study-guides/PL-300) | documentação oficial | competências Power Query, DAX, modelagem, visualização, segurança e atualização | escopo de certificação, não pesquisa de mercado |
| [Microsoft: esquema estrela](https://learn.microsoft.com/en-us/power-bi/guidance/star-schema) | documentação oficial | dimensões, fatos, grão e relacionamentos | orientação geral; exige adaptação ao domínio |
| [Microsoft: orientação para tabelas de data](https://learn.microsoft.com/en-us/power-bi/guidance/model-date-tables) | documentação oficial | intervalo contínuo, anos completos e atributos da `DimDate` | o calendário organizacional ainda exige regras próprias |
| [Microsoft: definir tabelas de data no Desktop](https://learn.microsoft.com/en-us/power-bi/transform-model/desktop-date-tables) | documentação oficial | requisitos de unicidade, ausência de nulos e marcação da tabela de datas | a aplicação no Desktop ainda não foi validada neste ambiente |
| [Microsoft: função CALCULATE em DAX](https://learn.microsoft.com/en-us/dax/calculate-function-dax) | documentação oficial | alteração explícita do contexto de filtro das medidas | a medida ainda precisa ser executada no modelo semântico |
| [Microsoft: função DIVIDE em DAX](https://learn.microsoft.com/en-us/dax/divide-function-dax) | documentação oficial | cálculo seguro de razões e retorno vazio quando o denominador é zero | não corrige denominador conceitualmente incorreto |
| [Microsoft: DAX Query View](https://learn.microsoft.com/en-us/power-bi/transform-model/dax-query-view) | documentação oficial | executar medidas query-scoped e, depois da validação, aplicá-las explicitamente ao modelo | `DEFINE MEASURE` não persiste no modelo sem `Update model with changes` |
| [Microsoft: consultas DAX](https://learn.microsoft.com/en-us/dax/dax-queries) | documentação oficial | contrato `DEFINE` + `EVALUATE` e escopo das medidas de consulta | consulta válida ainda precisa ser executada contra o modelo real |
| [Microsoft: função ROW em DAX](https://learn.microsoft.com/en-us/dax/row-function-dax) | documentação oficial | retornar os 14 resultados reconciliáveis em uma linha | exige pares nome/expressão e não valida a semântica das medidas |
| [Microsoft: função KEEPFILTERS em DAX](https://learn.microsoft.com/en-us/dax/keepfilters-function-dax) | documentação oficial | preservar a interseção com filtros existentes nas medidas condicionais | não corrige filtros ou denominadores conceitualmente errados |
| [Microsoft: função COUNTROWS em DAX](https://learn.microsoft.com/en-us/dax/countrows-function-dax) | documentação oficial | contagem explícita de linhas de fatos e pontes | resultado depende do contexto de filtro do modelo |
| [Microsoft: incremental refresh](https://learn.microsoft.com/en-us/power-bi/connect-data/incremental-refresh-overview) | documentação oficial | particionamento, atualização incremental e DirectQuery | recursos de tempo real dependem de capacidade |
| [Microsoft: automatic page refresh](https://learn.microsoft.com/en-us/power-bi/create-reports/desktop-automatic-page-refresh) | documentação oficial | limites de atualização automática | Import não oferece atualização automática de página |
| [Microsoft: gateway para arquivos locais](https://learn.microsoft.com/en-us/power-bi/connect-data/refresh-desktop-file-local-drive) | documentação oficial | atualização de File/Folder no serviço | requer gateway instalado e disponível |
| [Microsoft: PBIP/TMDL](https://learn.microsoft.com/en-us/power-bi/developer/projects/projects-dataset) | documentação oficial | versionamento do modelo semântico | requer Power BI Desktop compatível |
| [Microsoft: real-time streaming](https://learn.microsoft.com/en-us/power-bi/connect-data/service-real-time-streaming) | documentação oficial | evitar nova dependência de streaming legado | criação de novos modelos será descontinuada após 31/10/2027 |
| [Microsoft Fabric Real-Time Intelligence](https://learn.microsoft.com/en-us/fabric/fundamentals/track-visualize-data) | documentação oficial | arquitetura futura de streaming/Eventstream | custo e licenciamento ainda precisam ser avaliados |
| [ISA-95](https://www.isa.org/standards-and-publications/isa-standards/isa-95-standard) | organização de norma | fronteiras IT/OT e integração níveis 3–4 | texto integral da norma pode exigir licença |
| [OPC UA Part 1](https://reference.opcfoundation.org/specs/OPC-10000-1/4) | especificação oficial | interoperabilidade e informação industrial | implementação precisa de análise de segurança e conformidade |
| [ISO 14224:2016](https://www.iso.org/standard/64076.html) | página oficial de norma | categorias de equipamento, falha e manutenção | escopo original é petróleo, petroquímica e gás; não alegar conformidade geral |
| [WEF Future of Jobs 2025](https://reports.weforum.org/docs/WEF_Future_of_Jobs_Report_2025.pdf) | relatório internacional | prioridade para big data, cibersegurança e letramento tecnológico | projeções agregadas, não específicas de Manaus |
| [Volkswagen: manutenção, processos digitais e Smart Manufacturing](https://br.linkedin.com/jobs/view/engenheiro-a-de-manut-e-instala%C3%A7%C3%B5es-processos-digitais-e-smart-manufacturing-at-volkswagen-caminh%C3%B5es-e-%C3%B4nibus-4476653001) | vaga atual | combinação Power BI, DAX, SQL, Python, PLC, SCADA, OPC UA, MQTT e IT/OT | uma vaga não representa todo o mercado |
| [Auren: manutenção e monitoramento de ativos](https://br.linkedin.com/jobs/view/engenheira-engenheiro-de-manuten%C3%A7%C3%A3o-iii-monitoramento-de-ativos-at-auren-energia-4477880516) | vaga atual | convergência entre condição de ativos, dados e Power Platform | contexto específico de energia eólica |
| [IEEE Access: SLR de ML supervisionado para manutenção preditiva](https://doi.org/10.1109/ACCESS.2025.3578686) | revisão sistemática | necessidade de dados reais, reprodutibilidade e avaliação rigorosa | acesso e detalhes metodológicos devem ser lidos antes de uso acadêmico |
| [Journal of Manufacturing Systems: AI-enhanced digital twins in maintenance](https://doi.org/10.1016/j.jmsy.2025.07.006) | revisão sistemática e entrevistas | arquitetura em camadas e lacuna pesquisa–prática | entrevistas concentradas na Suécia; não valida a implementação local |
| [Computers in Industry: digital twins in smart industries](https://doi.org/10.1016/j.compind.2025.104398) | revisão | enquadramento de digital twin e integração de dados | conceitos variam entre estudos |

Novas fontes devem ser adicionadas antes de usar seus dados ou conclusões no
software, relatório Power BI, README, artigo ou publicação profissional.
