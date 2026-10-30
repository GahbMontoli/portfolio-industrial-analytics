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
$CmmsRawSourcePath = Join-Path $CmmsRoot 'src\AssistentePatinho.App\sample-cmms-data.json'
$Sources = @(
    $H3ObservationsPath,
    $H3ExperimentPath,
    $FaultStudyPath,
    $FaultStudyManifestPath,
    $CmmsAssetsPath,
    $CmmsWorkOrdersPath,
    $CmmsChecksPath,
    $CmmsPartsPath,
    $CmmsManifestPath,
    $CmmsRawSourcePath
)

foreach ($source in $Sources) {
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Fonte obrigatória ausente: $source"
    }
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$IngestedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')

function Get-RelativeSourceLocator {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return [System.IO.Path]::GetRelativePath(
        $WorkspaceRoot,
        [System.IO.Path]::GetFullPath($Path)).Replace('\', '/')
}

function Get-DateKey {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Timestamp
    )

    if ([string]::IsNullOrWhiteSpace($Timestamp)) {
        return $null
    }

    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($Timestamp, [ref]$parsed)) {
        throw "Timestamp inválido para chave de data: $Timestamp"
    }

    return [int]$parsed.ToUniversalTime().ToString(
        'yyyyMMdd',
        [System.Globalization.CultureInfo]::InvariantCulture)
}

function Add-AnalyticKeys {
    param(
        [Parameter(Mandatory)]
        [object[]]$Rows,
        [Parameter(Mandatory)]
        [hashtable]$EvidenceKeyByNaturalKey,
        [Parameter(Mandatory)]
        [hashtable]$SourceKeyByNaturalKey,
        [string]$ObservedTimeBasis,
        [switch]$IncludeObservedDate
    )

    foreach ($row in $Rows) {
        $evidenceNaturalKey = "$($row.evidence_class)|$($row.quality_status)"
        if (-not $EvidenceKeyByNaturalKey.ContainsKey($evidenceNaturalKey)) {
            throw "Evidência sem dimensão correspondente: $evidenceNaturalKey"
        }

        $sourceNaturalKey = "$($row.project_id)|$($row.source_id)"
        if (-not $SourceKeyByNaturalKey.ContainsKey($sourceNaturalKey)) {
            throw "Fonte sem dimensão correspondente: $sourceNaturalKey"
        }

        $row | Add-Member -NotePropertyName evidence_key `
            -NotePropertyValue $EvidenceKeyByNaturalKey[$evidenceNaturalKey] -Force
        $row | Add-Member -NotePropertyName source_key `
            -NotePropertyValue $SourceKeyByNaturalKey[$sourceNaturalKey] -Force

        if ($IncludeObservedDate) {
            $row | Add-Member -NotePropertyName observed_date_key `
                -NotePropertyValue (Get-DateKey $row.observed_at_utc) -Force
            $row | Add-Member -NotePropertyName observed_time_basis `
                -NotePropertyValue $ObservedTimeBasis -Force
        }
    }
}

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

$CmmsRawSourceHash = (Get-FileHash -LiteralPath $CmmsRawSourcePath -Algorithm SHA256).
    Hash.ToLowerInvariant()
if ($CmmsManifest.sourceSha256 -ne $CmmsRawSourceHash) {
    throw 'A fonte bruta CMMS não corresponde ao hash declarado no manifesto.'
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

$EvidenceClasses = [ordered]@{
    synthetic = [ordered]@{
        label = 'Sintética'
        limit = 'Valida comportamento e fluxo do software; não representa medição de campo nem demonstra causalidade.'
    }
    official_raw = [ordered]@{
        label = 'Oficial bruta'
        limit = 'Reproduz a fonte oficial sem transformar associação estatística em causalidade.'
    }
    lab_observed = [ordered]@{
        label = 'Observada em laboratório'
        limit = 'Aplica-se somente às condições e instrumentos documentados no ensaio de laboratório.'
    }
    field_observed = [ordered]@{
        label = 'Observada em campo'
        limit = 'Aplica-se ao ativo, período e condições de campo documentados; generalizações exigem validação adicional.'
    }
    derived = [ordered]@{
        label = 'Derivada'
        limit = 'Resulta de cálculo ou transformação e herda as limitações das fontes e do método empregado.'
    }
}
$QualityStatuses = [ordered]@{
    valid = [ordered]@{
        label = 'Válida'
        limit = 'Aprovada nos critérios automatizados aplicáveis ao pacote.'
    }
    warning = [ordered]@{
        label = 'Com ressalva'
        limit = 'Usar com ressalva e investigar os avisos antes de qualquer decisão.'
    }
    rejected = [ordered]@{
        label = 'Rejeitada'
        limit = 'Não usar em análises ou decisões.'
    }
    raw_unvalidated = [ordered]@{
        label = 'Bruta não validada'
        limit = 'Não usar antes da validação e da promoção controlada de qualidade.'
    }
}

$EvidenceRows = [System.Collections.Generic.List[object]]::new()
$EvidenceRows.Add([pscustomobject][ordered]@{
    evidence_key = 'unknown'
    evidence_class = 'unknown'
    quality_status = 'unknown'
    class_label = 'Desconhecida'
    quality_label = 'Desconhecida'
    interpretation_limit = 'Classificação ausente; não utilizar para conclusões analíticas.'
    is_unknown = $true
})
foreach ($classEntry in $EvidenceClasses.GetEnumerator()) {
    foreach ($qualityEntry in $QualityStatuses.GetEnumerator()) {
        $EvidenceRows.Add([pscustomobject][ordered]@{
            evidence_key = "$($classEntry.Key)|$($qualityEntry.Key)"
            evidence_class = $classEntry.Key
            quality_status = $qualityEntry.Key
            class_label = $classEntry.Value.label
            quality_label = $qualityEntry.Value.label
            interpretation_limit = "$($classEntry.Value.limit) $($qualityEntry.Value.limit)"
            is_unknown = $false
        })
    }
}

$H3ObservationsHash = (Get-FileHash -LiteralPath $H3ObservationsPath -Algorithm SHA256).Hash.ToLowerInvariant()
$H3ExperimentHash = (Get-FileHash -LiteralPath $H3ExperimentPath -Algorithm SHA256).Hash.ToLowerInvariant()
$SourceRows = @(
    [pscustomobject][ordered]@{
        source_key = 'unknown'
        project_id = 'unknown'
        source_id = 'unknown'
        source_kind = 'unknown'
        source_uri = 'urn:gahbmontoli:portfolio:source:unknown'
        source_locator = 'unknown'
        source_sha256 = ''
        source_version = 'unknown'
        schema_version = 1
        evidence_class = 'unknown'
        license_status = 'not_evaluated'
        interpretation_limit = 'Fonte ausente; não utilizar para conclusões analíticas.'
        is_unknown = $true
    },
    [pscustomobject][ordered]@{
        source_key = "h3-monitor|h3-synthetic.csv|$H3ObservationsHash"
        project_id = 'h3-monitor'
        source_id = 'h3-synthetic.csv'
        source_kind = 'simulation_output'
        source_uri = 'urn:gahbmontoli:h3-monitor:dataset:h3-synthetic.csv'
        source_locator = Get-RelativeSourceLocator $H3ObservationsPath
        source_sha256 = $H3ObservationsHash
        source_version = "sha256:$H3ObservationsHash"
        schema_version = 1
        evidence_class = 'synthetic'
        license_status = 'not_evaluated'
        interpretation_limit = 'Série sintética; valida o software e não substitui medição de campo.'
        is_unknown = $false
    },
    [pscustomobject][ordered]@{
        source_key = "h3-monitor|h3-experiment-observations.csv|$H3ExperimentHash"
        project_id = 'h3-monitor'
        source_id = 'h3-experiment-observations.csv'
        source_kind = 'simulation_experiment_output'
        source_uri = 'urn:gahbmontoli:h3-monitor:dataset:h3-experiment-observations.csv'
        source_locator = Get-RelativeSourceLocator $H3ExperimentPath
        source_sha256 = $H3ExperimentHash
        source_version = "sha256:$H3ExperimentHash"
        schema_version = 1
        evidence_class = 'synthetic'
        license_status = 'not_evaluated'
        interpretation_limit = 'Experimento sintético; comparação de cenários não demonstra efeito causal em campo.'
        is_unknown = $false
    },
    [pscustomobject][ordered]@{
        source_key = "industrial-simulator-3d|fault-study.csv|$FaultStudyCsvHash"
        project_id = 'industrial-simulator-3d'
        source_id = 'fault-study.csv'
        source_kind = 'simulation_fault_study_output'
        source_uri = 'urn:gahbmontoli:industrial-simulator-3d:dataset:fault-study.csv'
        source_locator = Get-RelativeSourceLocator $FaultStudyPath
        source_sha256 = $FaultStudyCsvHash
        source_version = "sha256:$FaultStudyCsvHash"
        schema_version = 1
        evidence_class = 'synthetic'
        license_status = 'not_evaluated'
        interpretation_limit = $FaultStudyManifest.evidenceLimit
        is_unknown = $false
    },
    [pscustomobject][ordered]@{
        source_key = "copiloto-confiabilidade|sample-cmms-data.json|$CmmsRawSourceHash"
        project_id = 'copiloto-confiabilidade'
        source_id = 'sample-cmms-data.json'
        source_kind = 'synthetic_cmms_fixture'
        source_uri = 'urn:gahbmontoli:copiloto-confiabilidade:dataset:sample-cmms-data.json'
        source_locator = Get-RelativeSourceLocator $CmmsRawSourcePath
        source_sha256 = $CmmsRawSourceHash
        source_version = "sha256:$CmmsRawSourceHash"
        schema_version = 1
        evidence_class = 'synthetic'
        license_status = 'not_evaluated'
        interpretation_limit = $CmmsManifest.evidenceLimit
        is_unknown = $false
    }
)

$EvidenceKeyByNaturalKey = @{}
foreach ($row in $EvidenceRows) {
    $EvidenceKeyByNaturalKey["$($row.evidence_class)|$($row.quality_status)"] = $row.evidence_key
}
$SourceKeyByNaturalKey = @{}
foreach ($row in $SourceRows | Where-Object { -not $_.is_unknown }) {
    $SourceKeyByNaturalKey["$($row.project_id)|$($row.source_id)"] = $row.source_key
}

Add-AnalyticKeys -Rows $WorkOrders `
    -EvidenceKeyByNaturalKey $EvidenceKeyByNaturalKey `
    -SourceKeyByNaturalKey $SourceKeyByNaturalKey `
    -ObservedTimeBasis 'work_order_opened_at_utc' -IncludeObservedDate
foreach ($row in $WorkOrders) {
    $row | Add-Member -NotePropertyName opened_date_key `
        -NotePropertyValue (Get-DateKey $row.opened_at_utc) -Force
    $row | Add-Member -NotePropertyName closed_date_key `
        -NotePropertyValue (Get-DateKey $row.closed_at_utc) -Force
}
Add-AnalyticKeys -Rows $WorkOrderChecks `
    -EvidenceKeyByNaturalKey $EvidenceKeyByNaturalKey `
    -SourceKeyByNaturalKey $SourceKeyByNaturalKey
Add-AnalyticKeys -Rows $WorkOrderParts `
    -EvidenceKeyByNaturalKey $EvidenceKeyByNaturalKey `
    -SourceKeyByNaturalKey $SourceKeyByNaturalKey
Add-AnalyticKeys -Rows $H3Observations `
    -EvidenceKeyByNaturalKey $EvidenceKeyByNaturalKey `
    -SourceKeyByNaturalKey $SourceKeyByNaturalKey `
    -ObservedTimeBasis 'simulation_timestamp_utc' -IncludeObservedDate
Add-AnalyticKeys -Rows $H3Experiments `
    -EvidenceKeyByNaturalKey $EvidenceKeyByNaturalKey `
    -SourceKeyByNaturalKey $SourceKeyByNaturalKey `
    -ObservedTimeBasis 'source_file_last_write_utc_proxy' -IncludeObservedDate
Add-AnalyticKeys -Rows $FaultStudies `
    -EvidenceKeyByNaturalKey $EvidenceKeyByNaturalKey `
    -SourceKeyByNaturalKey $SourceKeyByNaturalKey `
    -ObservedTimeBasis 'package_exported_at_utc' -IncludeObservedDate

$DateTimestamps = [System.Collections.Generic.List[DateTimeOffset]]::new()
foreach ($row in @($WorkOrders) + @($H3Observations) + @($H3Experiments) + @($FaultStudies)) {
    $DateTimestamps.Add([DateTimeOffset]::Parse($row.observed_at_utc).ToUniversalTime())
}
foreach ($row in $WorkOrders | Where-Object { -not [string]::IsNullOrWhiteSpace($_.closed_at_utc) }) {
    $DateTimestamps.Add([DateTimeOffset]::Parse($row.closed_at_utc).ToUniversalTime())
}
if ($DateTimestamps.Count -eq 0) {
    throw 'Não há timestamps para construir DimDate.'
}

$MinimumYear = ($DateTimestamps | Sort-Object | Select-Object -First 1).Year
$MaximumYear = ($DateTimestamps | Sort-Object | Select-Object -Last 1).Year
$MonthNames = @(
    'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
    'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'
)
$DayNames = @('segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira', 'sexta-feira', 'sábado', 'domingo')
$DateRows = [System.Collections.Generic.List[object]]::new()
$CurrentDate = [DateTime]::new($MinimumYear, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
$LastDate = [DateTime]::new($MaximumYear, 12, 31, 0, 0, 0, [DateTimeKind]::Utc)
while ($CurrentDate -le $LastDate) {
    $DayOfWeekNumber = (([int]$CurrentDate.DayOfWeek + 6) % 7) + 1
    $QuarterNumber = [int][Math]::Ceiling($CurrentDate.Month / 3.0)
    $DateRows.Add([pscustomobject][ordered]@{
        date_key = [int]$CurrentDate.ToString('yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture)
        date = $CurrentDate.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        calendar_year = $CurrentDate.Year
        quarter_number = $QuarterNumber
        quarter_label = "T$QuarterNumber"
        month_number = $CurrentDate.Month
        month_name = $MonthNames[$CurrentDate.Month - 1]
        year_month_key = [int]$CurrentDate.ToString('yyyyMM', [System.Globalization.CultureInfo]::InvariantCulture)
        year_month = $CurrentDate.ToString('yyyy-MM', [System.Globalization.CultureInfo]::InvariantCulture)
        iso_year = [System.Globalization.ISOWeek]::GetYear($CurrentDate)
        iso_week_number = [System.Globalization.ISOWeek]::GetWeekOfYear($CurrentDate)
        day_of_month = $CurrentDate.Day
        day_of_week_number = $DayOfWeekNumber
        day_name = $DayNames[$DayOfWeekNumber - 1]
        is_weekday = $DayOfWeekNumber -le 5
        is_weekend = $DayOfWeekNumber -gt 5
    })
    $CurrentDate = $CurrentDate.AddDays(1)
}

$Outputs = [ordered]@{}
$Outputs.dim_project = Export-Table -Rows $Projects -FileName 'dim_project.csv'
$Outputs.dim_asset = Export-Table -Rows $Assets -FileName 'dim_asset.csv'
$Outputs.dim_date = Export-Table -Rows $DateRows.ToArray() -FileName 'dim_date.csv'
$Outputs.dim_evidence = Export-Table -Rows $EvidenceRows.ToArray() -FileName 'dim_evidence.csv'
$Outputs.dim_source = Export-Table -Rows $SourceRows -FileName 'dim_source.csv'
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
            path = Get-RelativeSourceLocator $_
            sha256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
    tables = [ordered]@{
        dim_project = $Projects.Count
        dim_asset = $Assets.Count
        dim_date = $DateRows.Count
        dim_evidence = $EvidenceRows.Count
        dim_source = $SourceRows.Count
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
