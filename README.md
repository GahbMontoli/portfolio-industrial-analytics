# Portfolio Industrial Analytics

Base de engenharia de dados e Power BI para integrar os projetos públicos de
Gabriel Montoli:

- H3 Climate Reliability Lab;
- Simulador Industrial 3D;
- Copiloto de Confiabilidade.

O objetivo não é apenas montar telas. O projeto organiza dados, proveniência,
qualidade, modelo dimensional, medidas e critérios de interpretação antes da
visualização.

## Princípios

1. CSV, JSON, Excel e APIs são fontes; não são o modelo analítico final.
2. Dados brutos permanecem imutáveis e identificados por hash quando aplicável.
3. Dados sintéticos, oficiais brutos e observações de campo nunca são misturados
   sem uma coluna explícita de classe de evidência.
4. O Power BI consome tabelas em esquema estrela com grão documentado.
5. Correlação, similaridade e resultado de simulação não são prova causal.
6. Indicadores exibem definição, unidade, período, atualização e limitações.
7. HTML deixa de ser o destino analítico principal; CSV/JSON, banco relacional e
   Power BI tornam-se o caminho oficial.

## Estratégia de atualização

| Etapa | Fonte | Modo Power BI | Latência realista | Uso |
| --- | --- | --- | --- | --- |
| MVP | Pasta local com CSV/JSON/XLSX | Import | Manual ou agendada | Portfólio e validação do modelo |
| Piloto | PostgreSQL ou SQL Server | Import incremental | Minutos/horas | Histórico consolidado |
| Operacional | PostgreSQL/SQL Server | DirectQuery | Próximo do tempo real | Monitoramento com atualização automática |
| Escala | Fabric Eventstream/Eventhouse | Direct Lake/DirectQuery | Streaming | Telemetria industrial autorizada |

Importação de arquivos locais não é tempo real. No serviço Power BI, atualização
de fontes locais exige gateway. Atualização automática de página depende de
DirectQuery ou modos compatíveis e dos limites de capacidade/licenciamento.

## Documentos

- [Plano mestre](docs/PLANO_MESTRE.md)
- [Modelo dimensional](docs/MODELO_DIMENSIONAL.md)
- [Catálogo inicial de KPIs](docs/CATALOGO_KPIS.md)
- [Política de evidências e fontes](docs/POLITICA_DE_EVIDENCIAS.md)
- [Registro inicial de fontes](docs/REGISTRO_DE_FONTES.md)
- [Montagem do relatório Power BI](docs/POWER_BI_SETUP.md)
- [Contrato comum de dados](schemas/common-record.schema.json)

## Primeiro marco executável

O primeiro relatório deverá ser criado como projeto Power BI (`.pbip`) para que
o modelo semântico em TMDL possa ser versionado. O MVP terá cinco páginas:

1. Visão executiva;
2. Manutenção e confiabilidade;
3. Risco higrotérmico H3;
4. Simulação e injeção de falhas;
5. Qualidade e proveniência dos dados.

Nenhum relatório será publicado publicamente com `Publish to web`. Distribuição,
workspace, RLS e gateway serão configurados somente depois de validar o ambiente
Power BI e o público autorizado.

## Gerar o pacote tabular do MVP

Primeiro gere o estudo de falhas do simulador:

```powershell
dotnet run --project ..\simulador-industrial\src\SimuladorIndustrial.Cli -c Release -- `
  --fault-study `
  --scene ..\simulador-industrial\samples\celula-envase.scene.json `
  --output ..\simulador-industrial\artifacts\fault-study.csv
```

Gere também a exportação tabular do Copiloto de Confiabilidade:

```powershell
..\assistente-patinho\Exportar-PowerBI.ps1
```

O arquivo versionado `config\source-lock.json` fixa os 10 artefatos consumidos
a 3 repositórios públicos, commits e hashes SHA-256 específicos. O gerador
valida esse lock automaticamente antes de criar o pacote. Para executar somente
o diagnóstico de proveniência:

```powershell
.\scripts\Test-PortfolioBiSourceLock.ps1
```

O relatório local fica em
`data\curated\source-lock-validation.json`. Uma árvore de origem suja é
registrada para auditoria, mas não invalida por si só um artefato já travado a
um commit anterior; arquivo, origem, commit ou hash divergente bloqueiam a carga.
As referências `origin/main` usadas são locais e nenhum `fetch` implícito é
feito.

Depois consolide e valide as tabelas:

```powershell
.\scripts\New-PortfolioBiDataset.ps1
.\scripts\Test-PortfolioBiDataset.ps1
.\scripts\Test-PortfolioBiKpis.ps1
.\scripts\Test-PortfolioBiMeasures.ps1
```

O diretório ignorado `data\curated` conterá onze CSVs, um manifesto gerado com
versão de esquema e relatórios de validação. Além das quatro tabelas fato, duas pontes e dimensões
de projeto e ativo, o pacote materializa `DimDate`, `DimEvidence` e `DimSource`.
A dimensão de fonte usa identificadores portáveis, sem publicar caminhos
absolutos da máquina, e versiona cada origem por seu SHA-256. O manifesto inclui
o hash do source lock e, para cada entrada, repositório, commit e método de
verificação.

O consolidado também confere o manifesto do estudo de falhas, incluindo
contagem e hashes da cena e do CSV. O pacote atual possui 1.085 linhas de fatos,
é inteiramente sintético e serve para desenvolver e testar o relatório, não
para representar uma planta real. As consultas em `power-query` são fontes M
textuais auditáveis; elas ainda precisam ser aplicadas e validadas no Power BI
Desktop antes de existir um PBIP/PBIX validado.

Os artefatos gerados permanecem ignorados nos repositórios de origem: o lock
publica seus hashes e a revisão associada, não os próprios bytes. Ele também não
prova qual binário executou o exportador; essa limitação permanece explícita por
método de verificação.

O terceiro comando reconcilia 14 KPIs e contratos de unidade diretamente entre
as quatro fontes registradas e os fatos curados. Ele verifica coerência temporal
de OS, umidade relativa, cadência e margem de ponto de orvalho, identidades dos
experimentos pareados e unidades do estudo de falhas. O resultado auditável é
gravado no diretório ignorado como
`data\curated\kpi-reconciliation.json`; consulte o
[catálogo de KPIs](docs/CATALOGO_KPIS.md) para definições e limitações.

O quarto comando valida estaticamente as 14 medidas query-scoped de
`powerbi\measures\IndustrialMeasures.dax` contra o esquema curado, o contrato de
medidas e a reconciliação. Ele comprova cobertura, referências, unidades,
formatos e aliases; não executa DAX nem altera um modelo semântico. O resultado
fica em `data\curated\measure-validation.json` com hashes e a limitação explícita.
O teste `scripts\Test-PortfolioBiMeasureMutations.ps1` executa um baseline válido
e confirma a rejeição de dez mutações de contrato sem tocar nos dados curados.
