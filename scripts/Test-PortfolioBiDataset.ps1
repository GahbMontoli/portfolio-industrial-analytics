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

Write-Host 'Pacote Power BI validado com sucesso.' -ForegroundColor Green
Write-Host ("Tabelas: {0}; fatos: {1:N0} linhas" -f `
    $ExpectedTables.Count,
    (($Facts | ForEach-Object { @(Import-Csv -LiteralPath (Join-Path $DataDirectory $_)).Count } | Measure-Object -Sum).Sum))
