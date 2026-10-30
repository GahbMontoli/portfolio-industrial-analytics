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
$CmmsPath = Join-Path $CmmsRoot 'src\AssistentePatinho.App\sample-cmms-data.json'
$Sources = @($H3ObservationsPath, $H3ExperimentPath, $FaultStudyPath, $CmmsPath)

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

$Cmms = Get-Content -LiteralPath $CmmsPath -Raw | ConvertFrom-Json -DateKind String
$Assets = @($Cmms.assets | ForEach-Object {
    [pscustomobject]@{
        project_id = 'copiloto-confiabilidade'
        asset_id = $_.id
        tag = $_.tag
        asset_name = $_.name
        category = $_.category
        model = $_.model
        location = $_.location
        criticality = $_.criticality
        evidence_class = 'synthetic'
        quality_status = 'valid'
        schema_version = 1
    }
})

$WorkOrders = @($Cmms.workOrders | ForEach-Object {
    $opened = [DateTimeOffset]::Parse($_.openedAt).ToUniversalTime()
    $closed = if ($null -ne $_.closedAt) {
        [DateTimeOffset]::Parse($_.closedAt).ToUniversalTime()
    } else {
        $null
    }
    [pscustomobject]@{
        schema_version = 1
        project_id = 'copiloto-confiabilidade'
        run_id = 'cmms-sample-v1'
        source_id = 'sample-cmms-data.json'
        asset_id = $_.assetId
        observed_at_utc = $opened.ToString('O')
        ingested_at_utc = $IngestedAtUtc
        evidence_class = 'synthetic'
        quality_status = 'valid'
        work_order_id = $_.id
        opened_at_utc = $opened.ToString('O')
        closed_at_utc = if ($null -ne $closed) { $closed.ToString('O') } else { $null }
        is_closed = $null -ne $closed
        duration_hours = if ($null -ne $closed) { [math]::Round(($closed - $opened).TotalHours, 3) } else { $null }
        status = $_.status
        priority = $_.priority
        failure_code = $_.failureCode
        title = $_.title
        has_cause = -not [string]::IsNullOrWhiteSpace($_.cause)
        has_resolution = -not [string]::IsNullOrWhiteSpace($_.resolution)
        checks_count = @($_.checks).Count
        parts_count = @($_.parts).Count
    }
})

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

$FaultStudyObservedAt = (Get-Item -LiteralPath $FaultStudyPath).LastWriteTimeUtc.ToString('O')
$FaultStudies = @(Import-Csv -LiteralPath $FaultStudyPath | ForEach-Object {
    [pscustomobject]@{
        schema_version = 1
        project_id = 'industrial-simulator-3d'
        run_id = 'filling-cell-fault-study-v1'
        source_id = 'fault-study.csv'
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
