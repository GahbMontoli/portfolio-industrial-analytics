[CmdletBinding()]
param(
    [string]$DataDirectory
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($DataDirectory)) {
    $DataDirectory = Join-Path $ProjectRoot 'data\curated'
}

$ExpectedTables = [ordered]@{
    dim_project = 'project_id'
    dim_asset = 'asset_id'
    fact_work_order = 'work_order_id'
    bridge_work_order_check = 'check_text'
    bridge_work_order_part = 'part_text'
    fact_h3_observation = 'observed_at_utc'
    fact_h3_experiment = 'intervention_id'
    fact_fault_study = 'scenario_id'
}

$ManifestPath = Join-Path $DataDirectory 'manifest.json'
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Manifesto ausente: $ManifestPath"
}
$Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($Manifest.schemaVersion -ne 1) {
    throw "Versão de manifesto não suportada: $($Manifest.schemaVersion)"
}

foreach ($entry in $ExpectedTables.GetEnumerator()) {
    $path = Join-Path $DataDirectory "$($entry.Key).csv"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Tabela ausente: $path"
    }
    $rows = @(Import-Csv -LiteralPath $path)
    if ($rows.Count -eq 0) {
        throw "Tabela vazia: $($entry.Key)"
    }
    if ($rows[0].PSObject.Properties.Name -notcontains $entry.Value) {
        throw "Coluna obrigatória $($entry.Value) ausente em $($entry.Key)."
    }
    $expectedCount = [int]$Manifest.tables.($entry.Key)
    if ($rows.Count -ne $expectedCount) {
        throw "Contagem divergente em $($entry.Key): manifesto=$expectedCount, arquivo=$($rows.Count)."
    }
}

$Projects = @(Import-Csv -LiteralPath (Join-Path $DataDirectory 'dim_project.csv'))
if (@($Projects.project_id | Sort-Object -Unique).Count -ne 3) {
    throw 'A dimensão de projetos não contém os três sistemas esperados.'
}
if (@($Projects.project_id | Sort-Object -Unique).Count -ne $Projects.Count) {
    throw 'A dimensão de projetos contém chaves duplicadas.'
}

$Facts = @(
    'fact_work_order.csv',
    'fact_h3_observation.csv',
    'fact_h3_experiment.csv',
    'fact_fault_study.csv'
)
foreach ($file in $Facts) {
    $rows = @(Import-Csv -LiteralPath (Join-Path $DataDirectory $file))
    foreach ($row in $rows) {
        if ([string]::IsNullOrWhiteSpace($row.project_id) -or
            [string]::IsNullOrWhiteSpace($row.run_id) -or
            $row.evidence_class -ne 'synthetic' -or
            [string]::IsNullOrWhiteSpace($row.quality_status)) {
            throw "Envelope comum inválido em $file."
        }
        $parsed = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse($row.observed_at_utc, [ref]$parsed)) {
            throw "Timestamp inválido em ${file}: $($row.observed_at_utc)"
        }
    }
}

foreach ($file in @('bridge_work_order_check.csv', 'bridge_work_order_part.csv')) {
    $rows = @(Import-Csv -LiteralPath (Join-Path $DataDirectory $file))
    foreach ($row in $rows) {
        if ([string]::IsNullOrWhiteSpace($row.project_id) -or
            [string]::IsNullOrWhiteSpace($row.run_id) -or
            [string]::IsNullOrWhiteSpace($row.work_order_id) -or
            $row.evidence_class -ne 'synthetic') {
            throw "Ponte CMMS inválida em $file."
        }
    }
}

$AssetRows = @(Import-Csv -LiteralPath (Join-Path $DataDirectory 'dim_asset.csv'))
$WorkOrderRows = @(Import-Csv -LiteralPath (Join-Path $DataDirectory 'fact_work_order.csv'))
$AssetIdValues = @($AssetRows | ForEach-Object { $_.asset_id })
$WorkOrderIdValues = @($WorkOrderRows | ForEach-Object { $_.work_order_id })

if (@($AssetIdValues | Sort-Object -Unique).Count -ne $AssetRows.Count) {
    throw 'A dimensão de ativos contém chaves duplicadas.'
}
if (@($WorkOrderIdValues | Sort-Object -Unique).Count -ne $WorkOrderRows.Count) {
    throw 'O fato de ordens contém chaves duplicadas.'
}

$AssetIds = [System.Collections.Generic.HashSet[string]]::new([string[]]$AssetIdValues)
$WorkOrderIds = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]$WorkOrderIdValues)

$CmmsContext = [pscustomobject]@{
    project_id = $AssetRows[0].project_id
    run_id = $AssetRows[0].run_id
    source_id = $AssetRows[0].source_id
    evidence_class = $AssetRows[0].evidence_class
    quality_status = $AssetRows[0].quality_status
}
if ($CmmsContext.project_id -ne 'copiloto-confiabilidade' -or
    [string]::IsNullOrWhiteSpace($CmmsContext.run_id) -or
    [string]::IsNullOrWhiteSpace($CmmsContext.source_id) -or
    $CmmsContext.evidence_class -ne 'synthetic' -or
    $CmmsContext.quality_status -ne 'valid') {
    throw 'Envelope-base CMMS incompatível com o pacote sintético.'
}

$CmmsRows = @($AssetRows) + @($WorkOrderRows)
foreach ($file in @('bridge_work_order_check.csv', 'bridge_work_order_part.csv')) {
    $CmmsRows += @(Import-Csv -LiteralPath (Join-Path $DataDirectory $file))
}
foreach ($row in $CmmsRows) {
    foreach ($property in $CmmsContext.PSObject.Properties.Name) {
        if ($row.$property -ne $CmmsContext.$property) {
            throw "Envelope CMMS divergente em $property."
        }
    }
}

foreach ($row in $WorkOrderRows) {
    if (-not $AssetIds.Contains($row.asset_id)) {
        throw "Ordem $($row.work_order_id) referencia ativo inexistente: $($row.asset_id)."
    }
}
foreach ($file in @('bridge_work_order_check.csv', 'bridge_work_order_part.csv')) {
    $bridgeRows = @(Import-Csv -LiteralPath (Join-Path $DataDirectory $file))
    $BridgeKeys = @($bridgeRows | ForEach-Object { "$($_.work_order_id)`u{001f}$($_.ordinal)" })
    if (@($BridgeKeys | Sort-Object -Unique).Count -ne $bridgeRows.Count) {
        throw "A ponte $file contém chave composta duplicada."
    }
    foreach ($row in $bridgeRows) {
        if (-not $WorkOrderIds.Contains($row.work_order_id)) {
            throw "Ponte $file referencia ordem inexistente: $($row.work_order_id)."
        }
    }
}

Write-Host 'Pacote Power BI validado com sucesso.' -ForegroundColor Green
Write-Host ("Tabelas: {0}; fatos: {1:N0} linhas" -f `
    $ExpectedTables.Count,
    (($Facts | ForEach-Object { @(Import-Csv -LiteralPath (Join-Path $DataDirectory $_)).Count } | Measure-Object -Sum).Sum))
