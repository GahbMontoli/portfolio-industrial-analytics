[CmdletBinding()]
param(
    [string]$DataDirectory,
    [string]$DaxPath,
    [string]$ContractPath,
    [string]$KpiReportPath,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($DataDirectory)) {
    $DataDirectory = Join-Path $ProjectRoot 'data\curated'
}
if ([string]::IsNullOrWhiteSpace($DaxPath)) {
    $DaxPath = Join-Path $ProjectRoot 'powerbi\measures\IndustrialMeasures.dax'
}
if ([string]::IsNullOrWhiteSpace($ContractPath)) {
    $ContractPath = Join-Path $ProjectRoot 'powerbi\measures\measure-contracts.json'
}
if ([string]::IsNullOrWhiteSpace($KpiReportPath)) {
    $KpiReportPath = Join-Path $DataDirectory 'kpi-reconciliation.json'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $DataDirectory 'measure-validation.json'
}

function Assert-Condition {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,
        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-UniqueValues {
    param(
        [Parameter(Mandatory)]
        [object[]]$Values,
        [Parameter(Mandatory)]
        [string]$Context
    )

    if (@($Values | Sort-Object -Unique).Count -ne $Values.Count) {
        throw "Valores duplicados em ${Context}."
    }
}

function Assert-SameSet {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Actual,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Expected,
        [Parameter(Mandatory)]
        [string]$Context
    )

    $actualSet = @($Actual | Sort-Object -Unique)
    $expectedSet = @($Expected | Sort-Object -Unique)
    $actualFingerprint = @($actualSet | ForEach-Object { [string]$_ }) -join "`n"
    $expectedFingerprint = @($expectedSet | ForEach-Object { [string]$_ }) -join "`n"
    if ($actualSet.Count -ne $expectedSet.Count -or
        $actualFingerprint -cne $expectedFingerprint) {
        throw "Conjunto divergente em ${Context}: esperado=[$($expectedSet -join ', ')]; atual=[$($actualSet -join ', ')]"
    }
}

function Assert-SamePath {
    param(
        [Parameter(Mandatory)]
        [string]$Actual,
        [Parameter(Mandatory)]
        [string]$Expected,
        [Parameter(Mandatory)]
        [string]$Context
    )

    $actualPath = [System.IO.Path]::GetFullPath($Actual).
        TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    $expectedPath = [System.IO.Path]::GetFullPath($Expected).
        TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    $comparison = if ([OperatingSystem]::IsWindows()) {
        [StringComparison]::OrdinalIgnoreCase
    }
    else {
        [StringComparison]::Ordinal
    }
    if (-not [string]::Equals($actualPath, $expectedPath, $comparison)) {
        throw "Caminho divergente em ${Context}: esperado=$expectedPath; atual=$actualPath"
    }
}

foreach ($requiredPath in @($DaxPath, $ContractPath, $KpiReportPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Artefato obrigatório ausente: $requiredPath"
    }
}

$Contract = Get-Content -LiteralPath $ContractPath -Raw | ConvertFrom-Json
$KpiReport = Get-Content -LiteralPath $KpiReportPath -Raw | ConvertFrom-Json
$Dax = Get-Content -LiteralPath $DaxPath -Raw
if ($Contract.schemaVersion -ne 1 -or
    $Contract.artifactKind -ne 'dax-query-measure-contract' -or
    $Contract.validationScope -ne 'static_contract_only') {
    throw 'Contrato de medidas DAX incompatível.'
}
if ($KpiReport.schemaVersion -ne 1 -or
    @($KpiReport.metrics).Count -eq 0) {
    throw 'Relatório de reconciliação de KPIs incompatível ou vazio.'
}
$ExpectedDaxPath = Join-Path (Split-Path -Parent $ContractPath) $Contract.canonicalQuery
$ExpectedKpiReportPath = Join-Path $ProjectRoot $Contract.reconciliationReport
Assert-SamePath $DaxPath $ExpectedDaxPath 'canonicalQuery'
Assert-SamePath $KpiReportPath $ExpectedKpiReportPath 'reconciliationReport'

$TableFiles = [ordered]@{
    DimProject = 'dim_project.csv'
    DimAsset = 'dim_asset.csv'
    DimDate = 'dim_date.csv'
    DimEvidence = 'dim_evidence.csv'
    DimSource = 'dim_source.csv'
    FactWorkOrder = 'fact_work_order.csv'
    BridgeWorkOrderCheck = 'bridge_work_order_check.csv'
    BridgeWorkOrderPart = 'bridge_work_order_part.csv'
    FactH3Observation = 'fact_h3_observation.csv'
    FactH3Experiment = 'fact_h3_experiment.csv'
    FactFaultStudy = 'fact_fault_study.csv'
}
$TableColumns = @{}
foreach ($entry in $TableFiles.GetEnumerator()) {
    $path = Join-Path $DataDirectory $entry.Value
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Tabela necessária ao contrato DAX ausente: $($entry.Value)"
    }
    $firstRow = @(Import-Csv -LiteralPath $path | Select-Object -First 1)
    if ($firstRow.Count -ne 1) {
        throw "Tabela necessária ao contrato DAX vazia: $($entry.Value)"
    }
    $TableColumns[$entry.Key] = @($firstRow[0].PSObject.Properties.Name)
}

$Contracts = @($Contract.measures)
$KpiMetrics = @($KpiReport.metrics)
Assert-Condition ($Contracts.Count -eq 14) `
    "O contrato deve conter exatamente 14 medidas; atual=$($Contracts.Count)."
Assert-Condition ($KpiMetrics.Count -eq 14) `
    "A reconciliação deve conter exatamente 14 KPIs; atual=$($KpiMetrics.Count)."
Assert-UniqueValues @($Contracts.metricId) 'measure-contracts.metricId'
Assert-UniqueValues @($Contracts.measureName) 'measure-contracts.measureName'
Assert-UniqueValues @($KpiMetrics.metric_id) 'kpi-reconciliation.metric_id'
Assert-Condition (@($KpiMetrics | Where-Object status -ne 'valid').Count -eq 0) `
    'Todos os KPIs devem estar reconciliados com status valid antes do contrato DAX.'

$DefineMatches = @([regex]::Matches($Dax, '(?im)^\s*DEFINE\s*$'))
$EvaluateMatches = @([regex]::Matches($Dax, '(?im)^\s*EVALUATE\s*$'))
Assert-Condition ($DefineMatches.Count -eq 1) `
    'A consulta DAX deve conter exatamente um bloco DEFINE.'
Assert-Condition ($EvaluateMatches.Count -eq 1) `
    'A consulta DAX deve conter exatamente um bloco EVALUATE.'
Assert-Condition ($DefineMatches[0].Index -lt $EvaluateMatches[0].Index) `
    'O bloco DEFINE deve preceder EVALUATE.'

$DefinitionPattern = [regex]::new(
    '(?im)^\s*MEASURE\s+''(?<table>[^'']+)''\[(?<name>[^\]]+)\]\s*=')
$DefinitionMatches = @($DefinitionPattern.Matches($Dax))
$MarkerPattern = [regex]::new(
    '(?im)^\s*//\s*@metric-id\s+(?<metric>[a-z0-9_]+)\s*$')
$MarkerMatches = @($MarkerPattern.Matches($Dax))
$CombinedPattern = [regex]::new(
    '(?im)^\s*//\s*@metric-id\s+(?<metric>[a-z0-9_]+)\s*\r?\n' +
    '\s*MEASURE\s+''(?<table>[^'']+)''\[(?<name>[^\]]+)\]\s*=')
$CombinedMatches = @($CombinedPattern.Matches($Dax))

Assert-Condition ($DefinitionMatches.Count -eq $Contracts.Count) `
    'Quantidade de definições MEASURE divergente do contrato.'
Assert-Condition ($MarkerMatches.Count -eq $Contracts.Count) `
    'Cada medida deve possuir exatamente um marcador @metric-id.'
Assert-Condition ($CombinedMatches.Count -eq $Contracts.Count) `
    'Cada marcador @metric-id deve estar imediatamente acima de sua medida.'
Assert-UniqueValues @($MarkerMatches | ForEach-Object { $_.Groups['metric'].Value }) `
    'marcadores @metric-id'
Assert-UniqueValues @($DefinitionMatches | ForEach-Object { $_.Groups['name'].Value }) `
    'nomes globais de medidas DAX'
Assert-UniqueValues @($DefinitionMatches | ForEach-Object {
    "$($_.Groups['table'].Value)|$($_.Groups['name'].Value)"
}) 'definições de medidas DAX'

$ContractIds = @($Contracts.metricId)
$KpiIds = @($KpiMetrics.metric_id)
$MarkerIds = @($MarkerMatches | ForEach-Object { $_.Groups['metric'].Value })
Assert-SameSet $MarkerIds $ContractIds 'DAX markers versus measure contracts'
Assert-SameSet $KpiIds $ContractIds 'KPI reconciliation versus measure contracts'

$AllowedFormatsByUnit = @{
    count = '0'
    ratio = '0.0%'
    h = '0.00 "h"'
    '°C' = '0.000 "°C"'
    'h/replication' = '0.000 "h/réplica"'
    '°C/replication' = '0.000 "°C/réplica"'
    L = '0.000 "L"'
}
$KpiById = @{}
foreach ($metric in $KpiMetrics) {
    $KpiById[$metric.metric_id] = $metric
}
$ContractById = @{}
foreach ($measureContract in $Contracts) {
    $ContractById[$measureContract.metricId] = $measureContract
}

$ValidatedMeasures = [System.Collections.Generic.List[object]]::new()
for ($index = 0; $index -lt $CombinedMatches.Count; $index++) {
    $match = $CombinedMatches[$index]
    $metricId = $match.Groups['metric'].Value
    $homeTable = $match.Groups['table'].Value
    $measureName = $match.Groups['name'].Value
    $contractEntry = $ContractById[$metricId]
    Assert-Condition ($null -ne $contractEntry) `
        "Marcador DAX sem contrato: $metricId"
    Assert-Condition ($contractEntry.homeTable -eq $homeTable -and
        $contractEntry.measureName -eq $measureName) `
        "Definição DAX divergente do contrato para $metricId."
    Assert-Condition ($TableColumns.ContainsKey($homeTable)) `
        "Tabela-base inexistente para ${metricId}: $homeTable"
    foreach ($property in @(
        'unit', 'formatString', 'displayFolder', 'description', 'interpretationLimit'
    )) {
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($contractEntry.$property)) `
            "Propriedade $property ausente no contrato de $metricId."
    }
    Assert-Condition ($AllowedFormatsByUnit.ContainsKey($contractEntry.unit)) `
        "Unidade sem formato controlado em ${metricId}: $($contractEntry.unit)"
    Assert-Condition ($contractEntry.formatString -eq
        $AllowedFormatsByUnit[$contractEntry.unit]) `
        "Formato incompatível com a unidade em $metricId."

    $kpi = $KpiById[$metricId]
    Assert-Condition ($kpi.status -eq 'valid' -and
        $kpi.unit -eq $contractEntry.unit -and
        $kpi.interpretation_limit -eq $contractEntry.interpretationLimit) `
        "Contrato DAX divergente da reconciliação em $metricId."

    $expressionStart = $match.Index + $match.Length
    $expressionEnd = if ($index -lt $CombinedMatches.Count - 1) {
        $CombinedMatches[$index + 1].Index
    }
    else {
        $EvaluateMatches[0].Index
    }
    $expression = $Dax.Substring($expressionStart, $expressionEnd - $expressionStart)

    $unqualifiedColumns = @([regex]::Matches(
        $expression,
        '(?<!'')\b[A-Za-z_][A-Za-z0-9_]*\[[^\]]+\]'))
    Assert-Condition ($unqualifiedColumns.Count -eq 0) `
        "Referência de coluna não qualificada em $metricId."

    $ColumnReferencePattern = [regex]::new(
        '''(?<table>[^'']+)''\[(?<column>[^\]]+)\]')
    $columnReferences = @($ColumnReferencePattern.Matches($expression) |
        ForEach-Object {
            "$($_.Groups['table'].Value).$($_.Groups['column'].Value)"
        } | Sort-Object -Unique)
    foreach ($reference in $columnReferences) {
        $separator = $reference.IndexOf('.')
        $tableName = $reference.Substring(0, $separator)
        $columnName = $reference.Substring($separator + 1)
        Assert-Condition ($TableColumns.ContainsKey($tableName)) `
            "Tabela inexistente referenciada em ${metricId}: $tableName"
        Assert-Condition ($TableColumns[$tableName] -contains $columnName) `
            "Coluna inexistente referenciada em ${metricId}: $reference"
    }

    $tableReferences = @([regex]::Matches($expression, '''(?<table>[^'']+)''') |
        ForEach-Object { $_.Groups['table'].Value } | Sort-Object -Unique)
    foreach ($tableName in $tableReferences) {
        Assert-Condition ($TableColumns.ContainsKey($tableName)) `
            "Tabela inexistente referenciada em ${metricId}: $tableName"
    }
    Assert-SameSet $tableReferences @($contractEntry.tableDependencies) `
        "dependências de tabela de $metricId"
    Assert-SameSet $columnReferences @($contractEntry.columnDependencies) `
        "dependências de coluna de $metricId"

    $ValidatedMeasures.Add([pscustomobject][ordered]@{
        metric_id = $metricId
        home_table = $homeTable
        measure_name = $measureName
        unit = $contractEntry.unit
        format_string = $contractEntry.formatString
        display_folder = $contractEntry.displayFolder
        reconciled_fact_value = $kpi.fact_value
        reconciled_source_value = $kpi.source_value
        reconciliation_tolerance = $kpi.tolerance
        evidence_class = $kpi.evidence_class
        status = 'static_contract_valid'
        interpretation_limit = $contractEntry.interpretationLimit
    }) | Out-Null
}

$EvaluateSection = $Dax.Substring($EvaluateMatches[0].Index)
Assert-Condition ([regex]::IsMatch($EvaluateSection, '(?is)\bROW\s*\(')) `
    'EVALUATE deve retornar uma única linha por meio de ROW().'
$RowOutputPattern = [regex]::new(
    '"(?<alias>(?:[^"]|"")*)"\s*,',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$RowOutputMatches = @($RowOutputPattern.Matches($EvaluateSection))
Assert-Condition ($RowOutputMatches.Count -eq $Contracts.Count) `
    'EVALUATE ROW contém quantidade inesperada de aliases ou saídas adicionais.'
$RowOutputIds = @($RowOutputMatches | ForEach-Object {
    $_.Groups['alias'].Value.Replace('""', '"')
})
Assert-UniqueValues $RowOutputIds 'todos os aliases de EVALUATE ROW'
Assert-SameSet $RowOutputIds $ContractIds 'todos os aliases de EVALUATE ROW versus contratos'
$AliasPattern = [regex]::new(
    '"(?<metric>[a-z0-9_]+)"\s*,\s*\[(?<measure>[^\]]+)\]',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$AliasMatches = @($AliasPattern.Matches($EvaluateSection))
Assert-Condition ($AliasMatches.Count -eq $Contracts.Count) `
    'EVALUATE ROW deve conter exatamente uma saída por contrato.'
$AliasIds = @($AliasMatches | ForEach-Object { $_.Groups['metric'].Value })
$AliasMeasureNames = @($AliasMatches | ForEach-Object { $_.Groups['measure'].Value })
Assert-UniqueValues $AliasIds 'aliases de EVALUATE ROW'
Assert-UniqueValues $AliasMeasureNames 'medidas de EVALUATE ROW'
Assert-SameSet $AliasIds $ContractIds 'EVALUATE ROW versus measure contracts'
foreach ($alias in $AliasMatches) {
    $metricId = $alias.Groups['metric'].Value
    $measureName = $alias.Groups['measure'].Value
    Assert-Condition ($ContractById[$metricId].measureName -eq $measureName) `
        "Alias EVALUATE ROW aponta para medida incorreta em $metricId."
}

$Output = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
    validationScope = 'static_contract_only'
    daxExecutionStatus = 'not_run'
    semanticModelUpdateStatus = 'not_applied'
    evidenceNotice = 'Os KPIs reconciliados são sintéticos. Este relatório não comprova execução da consulta no Power BI.'
    artifacts = [ordered]@{
        daxQuery = [ordered]@{
            path = [System.IO.Path]::GetFileName($DaxPath)
            sha256 = (Get-FileHash -LiteralPath $DaxPath -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        measureContract = [ordered]@{
            path = [System.IO.Path]::GetFileName($ContractPath)
            sha256 = (Get-FileHash -LiteralPath $ContractPath -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        kpiReconciliation = [ordered]@{
            path = [System.IO.Path]::GetFileName($KpiReportPath)
            sha256 = (Get-FileHash -LiteralPath $KpiReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    summary = [ordered]@{
        contractedMeasures = $Contracts.Count
        staticValidMeasures = $ValidatedMeasures.Count
        reconciledMetrics = $KpiMetrics.Count
    }
    limitations = @(
        'Regex valida estrutura e referências, não toda a gramática DAX.',
        'Sintaxe, contexto de filtro e resultados exigem execução na DAX Query View.',
        'DEFINE MEASURE permanece query-scoped até atualização explícita do modelo.'
    )
    measures = @($ValidatedMeasures)
}
$OutputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$Output | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8

Write-Host 'Contratos de medidas Power BI validados estaticamente.' -ForegroundColor Green
Write-Host ("Medidas: {0}; KPIs reconciliados: {1}; execução DAX: não realizada; relatório: {2}" -f `
    $ValidatedMeasures.Count, $KpiMetrics.Count, $OutputPath)
