[CmdletBinding()]
param(
    [string]$H3Root,
    [string]$SimulatorRoot,
    [string]$CmmsRoot,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$WorkspaceRoot = Split-Path -Parent $ProjectRoot

if ([string]::IsNullOrWhiteSpace($H3Root)) {
    $H3Root = Join-Path $WorkspaceRoot 'h3-monitor'
}
if ([string]::IsNullOrWhiteSpace($SimulatorRoot)) {
    $SimulatorRoot = Join-Path $WorkspaceRoot 'simulador-industrial'
}
if ([string]::IsNullOrWhiteSpace($CmmsRoot)) {
    $CmmsRoot = Join-Path $WorkspaceRoot 'assistente-patinho'
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $ProjectRoot 'data\curated'
}

$H3ObservationsPath = Join-Path $H3Root 'output\validation\h3-synthetic.csv'
$H3ExperimentPath = Join-Path $H3Root 'output\validation-research\h3-experiment-observations.csv'
$FaultStudyPath = Join-Path $SimulatorRoot 'artifacts\fault-study.csv'
$FaultStudyManifestPath = [System.IO.Path]::ChangeExtension($FaultStudyPath, '.manifest.json')
$CmmsExportDirectory = Join-Path $CmmsRoot 'artifacts\power-bi'
$CmmsAssetsPath = Join-Path $CmmsExportDirectory 'dim_asset.csv'
$CmmsWorkOrdersPath = Join-Path $CmmsExportDirectory 'fact_work_order.csv'
$CmmsChecksPath = Join-Path $CmmsExportDirectory 'bridge_work_order_check.csv'
$CmmsPartsPath = Join-Path $CmmsExportDirectory 'bridge_work_order_part.csv'
$CmmsManifestPath = Join-Path $CmmsExportDirectory 'manifest.json'
$Sources = @(
    $H3ObservationsPath,
    $H3ExperimentPath,
    $FaultStudyPath,
    $FaultStudyManifestPath,
    $CmmsAssetsPath,
    $CmmsWorkOrdersPath,
    $CmmsChecksPath,
    $CmmsPartsPath,
    $CmmsManifestPath
)

foreach ($source in $Sources) {
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Fonte obrigatória ausente: $source"
    }
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$IngestedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')

function Export-Table {
    param(
        [Parameter(Mandatory)]
        [object[]]$Rows,
        [Parameter(Mandatory)]
        [string]$FileName
    )

    if ($Rows.Count -eq 0) {
        throw "A tabela $FileName não possui linhas."
    }

    $path = Join-Path $OutputDirectory $FileName
    $Rows | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding utf8
    return $path
}

$Projects = @(
    [pscustomobject]@{ project_id = 'h3-monitor'; project_name = 'H3 Climate Reliability Lab'; domain = 'Clima e confiabilidade' },
    [pscustomobject]@{ project_id = 'industrial-simulator-3d'; project_name = 'Simulador Industrial 3D'; domain = 'Automação e simulação' },
    [pscustomobject]@{ project_id = 'copiloto-confiabilidade'; project_name = 'Copiloto de Confiabilidade'; domain = 'Manutenção e CMMS' }
)

$Assets = @(Import-Csv -LiteralPath $CmmsAssetsPath)
$WorkOrders = @(Import-Csv -LiteralPath $CmmsWorkOrdersPath)
$WorkOrderChecks = @(Import-Csv -LiteralPath $CmmsChecksPath)
$WorkOrderParts = @(Import-Csv -LiteralPath $CmmsPartsPath)
$CmmsManifest = Get-Content -LiteralPath $CmmsManifestPath -Raw | ConvertFrom-Json

if ($CmmsManifest.schemaVersion -ne 1 -or
    $CmmsManifest.projectId -ne 'copiloto-confiabilidade' -or
    $CmmsManifest.evidenceClass -ne 'synthetic') {
    throw 'Manifesto CMMS incompatível com o contrato esperado.'
}

$CmmsExpectedCounts = [ordered]@{
    dimAsset = $Assets.Count
    factWorkOrder = $WorkOrders.Count
    bridgeWorkOrderCheck = $WorkOrderChecks.Count
    bridgeWorkOrderPart = $WorkOrderParts.Count
}
foreach ($entry in $CmmsExpectedCounts.GetEnumerator()) {
    if ([int]$CmmsManifest.tables.($entry.Key) -ne $entry.Value) {
        throw "Contagem CMMS divergente em $($entry.Key): manifesto=$($CmmsManifest.tables.($entry.Key)), arquivo=$($entry.Value)."
    }
}

$H3Observations = @(Import-Csv -LiteralPath $H3ObservationsPath -Delimiter ';' | ForEach-Object {
    $timestamp = [DateTimeOffset]::Parse($_.timestamp).ToUniversalTime()
    [pscustomobject]@{
        schema_version = 1
        project_id = 'h3-monitor'
        run_id = 'h3-validation'
        source_id = 'h3-synthetic.csv'
        asset_id = $null
        observed_at_utc = $timestamp.ToString('O')
        ingested_at_utc = $IngestedAtUtc
        evidence_class = 'synthetic'
        quality_status = 'valid'
        outdoor_temperature_c = $_.outdoor_temperature_c
        outdoor_rh_percent = $_.outdoor_rh_percent
        indoor_temperature_c = $_.indoor_temperature_c
        indoor_rh_percent = $_.indoor_rh_percent
        surface_temperature_c = $_.surface_temperature_c
        dew_point_c = $_.dew_point_c
        dew_point_margin_c = $_.dew_point_margin_c
        risk_level = $_.risk_level
        door_open = $_.door_open
        hvac_active = $_.hvac_active
        scenario_id = $_.scenario_tag
        interval_minutes = 10
    }
})

$H3ExperimentObservedAt = (Get-Item -LiteralPath $H3ExperimentPath).LastWriteTimeUtc.ToString('O')
$H3Experiments = @(Import-Csv -LiteralPath $H3ExperimentPath -Delimiter ';' | ForEach-Object {
    [pscustomobject]@{
        schema_version = 1
        project_id = 'h3-monitor'
        run_id = 'h3-validation-research'
        source_id = 'h3-experiment-observations.csv'
        asset_id = $null
        observed_at_utc = $H3ExperimentObservedAt
        ingested_at_utc = $IngestedAtUtc
        evidence_class = 'synthetic'
        quality_status = 'valid'
        replication = $_.replication
        seed = $_.seed
        intervention_id = $_.intervention_id
        baseline_exposure_hours = $_.baseline_exposure_hours
        intervention_exposure_hours = $_.intervention_exposure_hours
        exposure_hours_avoided = $_.exposure_hours_avoided
        baseline_high_risk_events = $_.baseline_high_risk_events
        intervention_high_risk_events = $_.intervention_high_risk_events
        high_risk_events_avoided = $_.high_risk_events_avoided
        baseline_minimum_margin_c = $_.baseline_minimum_margin_c
        intervention_minimum_margin_c = $_.intervention_minimum_margin_c
        minimum_margin_gain_c = $_.minimum_margin_gain_c
    }
})

$FaultStudySourceRows = @(Import-Csv -LiteralPath $FaultStudyPath)
$FaultStudyManifest = Get-Content -LiteralPath $FaultStudyManifestPath -Raw |
    ConvertFrom-Json -DateKind String
$FaultStudyCsvHash = (Get-FileHash -LiteralPath $FaultStudyPath -Algorithm SHA256).Hash.ToLowerInvariant()
$FaultStudySourcePath = Join-Path $SimulatorRoot "samples\$($FaultStudyManifest.sourceId)"

if ($FaultStudyManifest.schemaVersion -ne 1 -or
    $FaultStudyManifest.projectId -ne 'industrial-simulator-3d' -or
    $FaultStudyManifest.evidenceClass -ne 'synthetic' -or
    [int]$FaultStudyManifest.rowCount -ne $FaultStudySourceRows.Count -or
    $FaultStudyManifest.csvFile -ne (Split-Path -Leaf $FaultStudyPath) -or
    $FaultStudyManifest.csvSha256 -ne $FaultStudyCsvHash -or
    -not (Test-Path -LiteralPath $FaultStudySourcePath -PathType Leaf) -or
    $FaultStudyManifest.sourceSha256 -ne
        (Get-FileHash -LiteralPath $FaultStudySourcePath -Algorithm SHA256).Hash.ToLowerInvariant()) {
    throw 'Manifesto do estudo de falhas incompatível ou com integridade inválida.'
}

$FaultStudyObservedAt = [DateTimeOffset]::Parse(
    $FaultStudyManifest.exportedAtUtc).ToUniversalTime().ToString('O')
$FaultStudies = @($FaultStudySourceRows | ForEach-Object {
    [pscustomobject]@{
        schema_version = 1
        project_id = 'industrial-simulator-3d'
        run_id = $FaultStudyManifest.runId
        source_id = $FaultStudyManifest.csvFile
        asset_id = $null
        observed_at_utc = $FaultStudyObservedAt
        ingested_at_utc = $IngestedAtUtc
        evidence_class = 'synthetic'
        quality_status = if ($_.expectationMet -eq 'True') { 'valid' } else { 'warning' }
        scenario_id = $_.scenario
        expectation_met = $_.expectationMet
        simulated_seconds = $_.simulatedSeconds
        target_reached_at_seconds = $_.targetReachedAtSeconds
        final_physical_volume_liters = $_.finalPhysicalVolumeLiters
        final_reported_volume_liters = $_.finalReportedVolumeLiters
        maximum_sensor_deviation_liters = $_.maximumSensorDeviationLiters
        valve_open_at_capacity_steps = $_.valveOpenAtCapacitySteps
        valve_command_divergence_steps = $_.valveCommandDivergenceSteps
        final_valve_command = $_.finalValveCommand
        final_valve_effective_state = $_.finalValveEffectiveState
        observation = $_.observation
    }
})

$Outputs = [ordered]@{}
$Outputs.dim_project = Export-Table -Rows $Projects -FileName 'dim_project.csv'
$Outputs.dim_asset = Export-Table -Rows $Assets -FileName 'dim_asset.csv'
$Outputs.fact_work_order = Export-Table -Rows $WorkOrders -FileName 'fact_work_order.csv'
$Outputs.bridge_work_order_check = Export-Table -Rows $WorkOrderChecks -FileName 'bridge_work_order_check.csv'
$Outputs.bridge_work_order_part = Export-Table -Rows $WorkOrderParts -FileName 'bridge_work_order_part.csv'
$Outputs.fact_h3_observation = Export-Table -Rows $H3Observations -FileName 'fact_h3_observation.csv'
$Outputs.fact_h3_experiment = Export-Table -Rows $H3Experiments -FileName 'fact_h3_experiment.csv'
$Outputs.fact_fault_study = Export-Table -Rows $FaultStudies -FileName 'fact_fault_study.csv'

$Manifest = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = $IngestedAtUtc
    evidenceNotice = 'Todas as linhas deste pacote são sintéticas e validam somente o comportamento dos softwares.'
    sources = @($Sources | ForEach-Object {
        [ordered]@{
            path = [System.IO.Path]::GetFullPath($_)
            sha256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
    tables = [ordered]@{
        dim_project = $Projects.Count
        dim_asset = $Assets.Count
        fact_work_order = $WorkOrders.Count
        bridge_work_order_check = $WorkOrderChecks.Count
        bridge_work_order_part = $WorkOrderParts.Count
        fact_h3_observation = $H3Observations.Count
        fact_h3_experiment = $H3Experiments.Count
        fact_fault_study = $FaultStudies.Count
    }
}
$ManifestPath = Join-Path $OutputDirectory 'manifest.json'
$Manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ManifestPath -Encoding utf8

Write-Host "Pacote Power BI criado em: $OutputDirectory"
$Manifest.tables.GetEnumerator() | ForEach-Object {
    Write-Host ("{0}: {1} linhas" -f $_.Key, $_.Value)
}
