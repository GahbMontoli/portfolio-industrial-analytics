[CmdletBinding()]
param(
    [string]$DataDirectory,
    [string]$WorkspaceRoot,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Split-Path -Parent $ProjectRoot
}
if ([string]::IsNullOrWhiteSpace($DataDirectory)) {
    $DataDirectory = Join-Path $ProjectRoot 'data\curated'
}
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $DataDirectory 'kpi-reconciliation.json'
}

$InvariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
$Metrics = [System.Collections.Generic.List[object]]::new()

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

function ConvertTo-InvariantDouble {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value,
        [Parameter(Mandatory)]
        [string]$Context
    )

    $parsed = 0.0
    if ([string]::IsNullOrWhiteSpace($Value) -or
        -not [double]::TryParse(
            $Value,
            [System.Globalization.NumberStyles]::Float,
            $InvariantCulture,
            [ref]$parsed) -or
        [double]::IsNaN($parsed) -or
        [double]::IsInfinity($parsed)) {
        throw "Número inválido em ${Context}: $Value"
    }
    return $parsed
}

function ConvertTo-OptionalInvariantDouble {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value,
        [Parameter(Mandatory)]
        [string]$Context
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }
    return ConvertTo-InvariantDouble -Value $Value -Context $Context
}

function ConvertTo-StrictBoolean {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value,
        [Parameter(Mandatory)]
        [string]$Context
    )

    $parsed = $false
    if (-not [bool]::TryParse($Value, [ref]$parsed)) {
        throw "Booleano inválido em ${Context}: $Value"
    }
    return $parsed
}

function ConvertTo-UtcTimestamp {
    param(
        [Parameter(Mandatory)]
        [string]$Value,
        [Parameter(Mandatory)]
        [string]$Context
    )

    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($Value, [ref]$parsed)) {
        throw "Timestamp inválido em ${Context}: $Value"
    }
    return $parsed.ToUniversalTime()
}

function Assert-Close {
    param(
        [Parameter(Mandatory)]
        [double]$Actual,
        [Parameter(Mandatory)]
        [double]$Expected,
        [Parameter(Mandatory)]
        [double]$Tolerance,
        [Parameter(Mandatory)]
        [string]$Context
    )

    if ([Math]::Abs($Actual - $Expected) -gt $Tolerance) {
        throw ("Divergência em {0}: atual={1:R}, esperado={2:R}, tolerância={3:R}." -f `
            $Context, $Actual, $Expected, $Tolerance)
    }
}

function Get-RequiredTable {
    param(
        [Parameter(Mandatory)]
        [string]$FileName,
        [char]$Delimiter = ','
    )

    $path = Join-Path $DataDirectory $FileName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Tabela obrigatória ausente: $path"
    }
    $rows = @(Import-Csv -LiteralPath $path -Delimiter $Delimiter)
    if ($rows.Count -eq 0) {
        throw "Tabela obrigatória vazia: $FileName"
    }
    return $rows
}

function Get-RegisteredSourcePath {
    param(
        [Parameter(Mandatory)]
        [object[]]$SourceRows,
        [Parameter(Mandatory)]
        [string]$ProjectId,
        [Parameter(Mandatory)]
        [string]$SourceId
    )

    $matches = @($SourceRows | Where-Object {
        $_.project_id -eq $ProjectId -and $_.source_id -eq $SourceId
    })
    if ($matches.Count -ne 1) {
        throw "DimSource não possui exatamente uma versão para $ProjectId/$SourceId."
    }
    $locator = $matches[0].source_locator
    if ([string]::IsNullOrWhiteSpace($locator) -or
        [System.IO.Path]::IsPathRooted($locator) -or
        $locator.Contains('\') -or
        @($locator.Split('/') | Where-Object { $_ -eq '..' }).Count -gt 0) {
        throw "Localizador de fonte não portável: $locator"
    }
    $resolvedWorkspace = [System.IO.Path]::GetFullPath($WorkspaceRoot).
        TrimEnd([System.IO.Path]::DirectorySeparatorChar) +
        [System.IO.Path]::DirectorySeparatorChar
    $path = [System.IO.Path]::GetFullPath((Join-Path $WorkspaceRoot $locator))
    if (-not $path.StartsWith(
            $resolvedWorkspace,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Fonte registrada fora do workspace permitido: $locator"
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Fonte registrada ausente: $($matches[0].source_locator)"
    }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $matches[0].source_sha256) {
        throw "Hash divergente para a fonte registrada: $($matches[0].source_locator)"
    }
    return $path
}

function Add-ReconciliationMetric {
    param(
        [Parameter(Mandatory)]
        [string]$Id,
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [double]$FactValue,
        [Parameter(Mandatory)]
        [double]$SourceValue,
        [Parameter(Mandatory)]
        [double]$Tolerance,
        [Parameter(Mandatory)]
        [string]$Unit,
        [AllowNull()]
        [object]$Numerator,
        [AllowNull()]
        [object]$Denominator,
        [Parameter(Mandatory)]
        [string]$Grain,
        [Parameter(Mandatory)]
        [string]$Filter,
        [Parameter(Mandatory)]
        [string]$InterpretationLimit
    )

    Assert-Close -Actual $FactValue -Expected $SourceValue `
        -Tolerance $Tolerance -Context $Name
    $Metrics.Add([pscustomobject][ordered]@{
        metric_id = $Id
        metric_name = $Name
        fact_value = $FactValue
        source_value = $SourceValue
        absolute_difference = [Math]::Abs($FactValue - $SourceValue)
        tolerance = $Tolerance
        numerator = $Numerator
        denominator = $Denominator
        unit = $Unit
        grain = $Grain
        filter = $Filter
        evidence_class = 'synthetic'
        status = 'valid'
        interpretation_limit = $InterpretationLimit
    }) | Out-Null
}

$SourceRows = Get-RequiredTable -FileName 'dim_source.csv'
$WorkOrders = Get-RequiredTable -FileName 'fact_work_order.csv'
$WorkOrderChecks = Get-RequiredTable -FileName 'bridge_work_order_check.csv'
$WorkOrderParts = Get-RequiredTable -FileName 'bridge_work_order_part.csv'
$H3Observations = Get-RequiredTable -FileName 'fact_h3_observation.csv'
$H3Experiments = Get-RequiredTable -FileName 'fact_h3_experiment.csv'
$FaultStudies = Get-RequiredTable -FileName 'fact_fault_study.csv'

$CmmsPath = Get-RegisteredSourcePath -SourceRows $SourceRows `
    -ProjectId 'copiloto-confiabilidade' -SourceId 'sample-cmms-data.json'
$H3Path = Get-RegisteredSourcePath -SourceRows $SourceRows `
    -ProjectId 'h3-monitor' -SourceId 'h3-synthetic.csv'
$H3ExperimentPath = Get-RegisteredSourcePath -SourceRows $SourceRows `
    -ProjectId 'h3-monitor' -SourceId 'h3-experiment-observations.csv'
$FaultStudyPath = Get-RegisteredSourcePath -SourceRows $SourceRows `
    -ProjectId 'industrial-simulator-3d' -SourceId 'fault-study.csv'

# CMMS: reconciliação por ordem e coerência temporal.
$Cmms = Get-Content -LiteralPath $CmmsPath -Raw | ConvertFrom-Json -DateKind String
$CmmsOrders = @($Cmms.workOrders)
Assert-Condition ($CmmsOrders.Count -eq $WorkOrders.Count) `
    'A quantidade de ordens diverge entre o JSON CMMS e FactWorkOrder.'
$CmmsIds = @($CmmsOrders.id)
$FactWorkOrderIds = @($WorkOrders.work_order_id)
Assert-Condition (@($CmmsIds | Sort-Object -Unique).Count -eq $CmmsOrders.Count) `
    'A fonte CMMS contém IDs de ordem duplicados.'
Assert-Condition (@($FactWorkOrderIds | Sort-Object -Unique).Count -eq $WorkOrders.Count) `
    'FactWorkOrder contém IDs duplicados.'

$CmmsById = @{}
foreach ($sourceOrder in $CmmsOrders) {
    $CmmsById[$sourceOrder.id] = $sourceOrder
}
$ChecksByOrder = @{}
foreach ($row in $WorkOrderChecks) {
    if (-not $ChecksByOrder.ContainsKey($row.work_order_id)) {
        $ChecksByOrder[$row.work_order_id] = 0
    }
    $ChecksByOrder[$row.work_order_id]++
}
$PartsByOrder = @{}
foreach ($row in $WorkOrderParts) {
    if (-not $PartsByOrder.ContainsKey($row.work_order_id)) {
        $PartsByOrder[$row.work_order_id] = 0
    }
    $PartsByOrder[$row.work_order_id]++
}

foreach ($factOrder in $WorkOrders) {
    Assert-Condition ($CmmsById.ContainsKey($factOrder.work_order_id)) `
        "Ordem curada ausente na fonte CMMS: $($factOrder.work_order_id)"
    $sourceOrder = $CmmsById[$factOrder.work_order_id]
    $opened = ConvertTo-UtcTimestamp -Value $sourceOrder.openedAt `
        -Context "$($sourceOrder.id).openedAt"
    $factOpened = ConvertTo-UtcTimestamp -Value $factOrder.opened_at_utc `
        -Context "$($factOrder.work_order_id).opened_at_utc"
    Assert-Condition ($opened -eq $factOpened) `
        "Abertura divergente na ordem $($factOrder.work_order_id)."

    $expectedClosed = -not [string]::IsNullOrWhiteSpace($sourceOrder.closedAt)
    $factClosed = ConvertTo-StrictBoolean -Value $factOrder.is_closed `
        -Context "$($factOrder.work_order_id).is_closed"
    Assert-Condition ($expectedClosed -eq $factClosed) `
        "Estado de encerramento divergente na ordem $($factOrder.work_order_id)."
    Assert-Condition ($factOrder.status -eq $sourceOrder.status) `
        "Status divergente na ordem $($factOrder.work_order_id)."

    if ($expectedClosed) {
        $closed = ConvertTo-UtcTimestamp -Value $sourceOrder.closedAt `
            -Context "$($sourceOrder.id).closedAt"
        $factClosedAt = ConvertTo-UtcTimestamp -Value $factOrder.closed_at_utc `
            -Context "$($factOrder.work_order_id).closed_at_utc"
        Assert-Condition ($closed -eq $factClosedAt -and $closed -ge $opened) `
            "Encerramento inválido na ordem $($factOrder.work_order_id)."
        $expectedDuration = ($closed - $opened).TotalHours
        $factDuration = ConvertTo-InvariantDouble -Value $factOrder.duration_hours `
            -Context "$($factOrder.work_order_id).duration_hours"
        Assert-Close -Actual $factDuration -Expected $expectedDuration `
            -Tolerance 0.001 -Context "$($factOrder.work_order_id).duration_hours"
    }
    else {
        Assert-Condition (
            [string]::IsNullOrWhiteSpace($factOrder.closed_at_utc) -and
            [string]::IsNullOrWhiteSpace($factOrder.closed_date_key) -and
            [string]::IsNullOrWhiteSpace($factOrder.duration_hours)) `
            "Ordem aberta contém dados de encerramento: $($factOrder.work_order_id)."
    }

    $expectedCause = -not [string]::IsNullOrWhiteSpace($sourceOrder.cause)
    $expectedResolution = -not [string]::IsNullOrWhiteSpace($sourceOrder.resolution)
    Assert-Condition (
        (ConvertTo-StrictBoolean $factOrder.has_cause "$($factOrder.work_order_id).has_cause") -eq $expectedCause -and
        (ConvertTo-StrictBoolean $factOrder.has_resolution "$($factOrder.work_order_id).has_resolution") -eq $expectedResolution) `
        "Completude divergente na ordem $($factOrder.work_order_id)."

    $expectedChecks = @($sourceOrder.checks).Count
    $expectedParts = @($sourceOrder.parts).Count
    $actualChecks = if ($ChecksByOrder.ContainsKey($factOrder.work_order_id)) {
        $ChecksByOrder[$factOrder.work_order_id]
    } else { 0 }
    $actualParts = if ($PartsByOrder.ContainsKey($factOrder.work_order_id)) {
        $PartsByOrder[$factOrder.work_order_id]
    } else { 0 }
    Assert-Condition (
        [int]$factOrder.checks_count -eq $expectedChecks -and
        [int]$factOrder.parts_count -eq $expectedParts -and
        $actualChecks -eq $expectedChecks -and
        $actualParts -eq $expectedParts) `
        "Contagens de checks/peças divergentes na ordem $($factOrder.work_order_id)."
}

$SourceClosedOrders = @($CmmsOrders | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_.closedAt)
})
$FactClosedOrders = @($WorkOrders | Where-Object {
    ConvertTo-StrictBoolean $_.is_closed "$($_.work_order_id).is_closed"
})
Assert-Condition ($SourceClosedOrders.Count -gt 0 -and $FactClosedOrders.Count -gt 0) `
    'MTTR e completude não podem ser reconciliados sem ordens encerradas.'
$SourceMttr = ($SourceClosedOrders | ForEach-Object {
    ((ConvertTo-UtcTimestamp $_.closedAt "$($_.id).closedAt") -
        (ConvertTo-UtcTimestamp $_.openedAt "$($_.id).openedAt")).TotalHours
} | Measure-Object -Average).Average
$FactMttr = ($FactClosedOrders | ForEach-Object {
    ConvertTo-InvariantDouble $_.duration_hours "$($_.work_order_id).duration_hours"
} | Measure-Object -Average).Average
$SourceComplete = @($SourceClosedOrders | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_.cause) -and
    -not [string]::IsNullOrWhiteSpace($_.resolution)
}).Count
$FactComplete = @($FactClosedOrders | Where-Object {
    (ConvertTo-StrictBoolean $_.has_cause "$($_.work_order_id).has_cause") -and
    (ConvertTo-StrictBoolean $_.has_resolution "$($_.work_order_id).has_resolution") -and
    -not [string]::IsNullOrWhiteSpace($_.closed_at_utc)
}).Count
$SourceCheckCount = ($CmmsOrders | ForEach-Object {
    @($_.checks).Count
} | Measure-Object -Sum).Sum
$SourcePartCount = ($CmmsOrders | ForEach-Object {
    @($_.parts).Count
} | Measure-Object -Sum).Sum

Add-ReconciliationMetric 'work_orders_open' 'Ordens abertas' `
    (@($WorkOrders | Where-Object is_closed -eq 'false').Count) `
    (@($CmmsOrders | Where-Object { [string]::IsNullOrWhiteSpace($_.closedAt) }).Count) `
    0 'count' $null $null 'uma ordem de serviço' 'is_closed = false' `
    'Contagem sintética; não representa backlog de uma planta real.'
Add-ReconciliationMetric 'work_orders_closed' 'Ordens encerradas' `
    $FactClosedOrders.Count $SourceClosedOrders.Count 0 'count' `
    $null $null 'uma ordem de serviço' 'is_closed = true' `
    'Contagem sintética; não comprova desempenho operacional.'
Add-ReconciliationMetric 'mttr_observed_hours' 'MTTR observado' `
    $FactMttr $SourceMttr 0.001 'h' $null $null 'uma ordem encerrada' `
    'is_closed = true; média de duration_hours' `
    'Tempo calendário entre abertura e encerramento; não é tempo ativo de reparo.'
Add-ReconciliationMetric 'closure_completeness_ratio' 'Completude de encerramento' `
    ([double]$FactComplete / $FactClosedOrders.Count) `
    ([double]$SourceComplete / $SourceClosedOrders.Count) 0.000000001 'ratio' `
    $FactComplete $FactClosedOrders.Count 'uma ordem encerrada' `
    'encerrada com causa, resolução e closed_at_utc' `
    'Mede preenchimento dos registros, não a qualidade técnica da solução.'
Add-ReconciliationMetric 'work_order_checks' 'Checks vinculados' `
    $WorkOrderChecks.Count $SourceCheckCount 0 'count' `
    $null $null 'um check por ordem e ordinal' 'sem filtro' `
    'Quantidade sintética de itens; não comprova execução em campo.'
Add-ReconciliationMetric 'work_order_parts' 'Peças vinculadas' `
    $WorkOrderParts.Count $SourcePartCount 0 'count' `
    $null $null 'uma peça por ordem e ordinal' 'sem filtro' `
    'Quantidade sintética; não representa consumo real de estoque.'

# H3: unidades, cadência e margens contra a série-fonte.
$H3Source = @(Import-Csv -LiteralPath $H3Path -Delimiter ';')
Assert-Condition ($H3Source.Count -eq $H3Observations.Count) `
    'A quantidade de observações H3 diverge da fonte.'
$AllowedRiskLevels = @('Normal', 'Elevated', 'High', 'Critical')
$OrderedH3Source = @($H3Source | Sort-Object {
    ConvertTo-UtcTimestamp $_.timestamp 'H3.timestamp'
})
Assert-Condition ($OrderedH3Source.Count -ge 2) `
    'A série H3 não possui observações suficientes para derivar a cadência.'
$H3Intervals = for ($index = 1; $index -lt $OrderedH3Source.Count; $index++) {
    $current = ConvertTo-UtcTimestamp $OrderedH3Source[$index].timestamp 'H3.timestamp'
    $previous = ConvertTo-UtcTimestamp $OrderedH3Source[$index - 1].timestamp 'H3.timestamp'
    ($current - $previous).TotalMinutes
}
$UniqueH3Intervals = @($H3Intervals | ForEach-Object {
    [Math]::Round($_, 9)
} | Sort-Object -Unique)
Assert-Condition ($UniqueH3Intervals.Count -eq 1 -and $UniqueH3Intervals[0] -gt 0) `
    'A série H3 possui cadência temporal irregular.'
$CadenceMinutes = [double]$UniqueH3Intervals[0]

$H3SourceByKey = @{}
foreach ($row in $H3Source) {
    Assert-Condition (ConvertTo-StrictBoolean $row.is_synthetic 'H3.is_synthetic') `
        'A fonte H3 atual deve permanecer explicitamente sintética.'
    Assert-Condition ($AllowedRiskLevels -contains $row.risk_level) `
        "Nível de risco H3 inválido: $($row.risk_level)"
    foreach ($rhColumn in @('outdoor_rh_percent', 'indoor_rh_percent')) {
        $rh = ConvertTo-InvariantDouble $row.$rhColumn "H3.$rhColumn"
        Assert-Condition ($rh -ge 0 -and $rh -le 100) `
            "Umidade relativa fora de 0..100% em H3.$rhColumn."
    }
    $surface = ConvertTo-InvariantDouble $row.surface_temperature_c 'H3.surface_temperature_c'
    $dewPoint = ConvertTo-InvariantDouble $row.dew_point_c 'H3.dew_point_c'
    $margin = ConvertTo-InvariantDouble $row.dew_point_margin_c 'H3.dew_point_margin_c'
    Assert-Close $margin ($surface - $dewPoint) 0.0011 'H3.dew_point_margin_c'
    $timestamp = ConvertTo-UtcTimestamp $row.timestamp 'H3.timestamp'
    $key = "$($row.scenario_tag)|$($timestamp.ToString('O'))"
    Assert-Condition (-not $H3SourceByKey.ContainsKey($key)) `
        "Chave H3 duplicada na fonte: $key"
    $H3SourceByKey[$key] = $row
}

$H3FactByKey = @{}
foreach ($row in $H3Observations) {
    $timestamp = ConvertTo-UtcTimestamp $row.observed_at_utc 'FactH3Observation.observed_at_utc'
    $key = "$($row.scenario_id)|$($timestamp.ToString('O'))"
    Assert-Condition ($H3SourceByKey.ContainsKey($key)) `
        "Observação H3 curada sem linha-fonte: $key"
    Assert-Condition (-not $H3FactByKey.ContainsKey($key)) `
        "Chave H3 duplicada no fato: $key"
    $H3FactByKey[$key] = $row
    $source = $H3SourceByKey[$key]
    Assert-Condition ($AllowedRiskLevels -contains $row.risk_level) `
        "Nível de risco curado inválido: $($row.risk_level)"
    Assert-Condition ($row.risk_level -eq $source.risk_level) `
        "Nível de risco divergente entre fonte e fato em $key."
    Assert-Condition ($row.evidence_class -eq 'synthetic') `
        "Classe de evidência H3 inválida em $key."
    $expectedCadence = $CadenceMinutes
    $actualCadence = ConvertTo-InvariantDouble $row.interval_minutes `
        'FactH3Observation.interval_minutes'
    Assert-Close $actualCadence $expectedCadence 0.000000001 `
        'FactH3Observation.interval_minutes'
    foreach ($numericColumn in @(
        'outdoor_temperature_c', 'outdoor_rh_percent',
        'indoor_temperature_c', 'indoor_rh_percent',
        'surface_temperature_c', 'dew_point_c', 'dew_point_margin_c'
    )) {
        $actual = ConvertTo-InvariantDouble $row.$numericColumn `
            "FactH3Observation.$numericColumn"
        $expected = ConvertTo-InvariantDouble $source.$numericColumn `
            "H3.$numericColumn"
        Assert-Close $actual $expected 0.000000001 `
            "FactH3Observation.$numericColumn[$key]"
    }
    foreach ($rhColumn in @('outdoor_rh_percent', 'indoor_rh_percent')) {
        $rh = ConvertTo-InvariantDouble $row.$rhColumn "FactH3Observation.$rhColumn"
        Assert-Condition ($rh -ge 0 -and $rh -le 100) `
            "Umidade relativa fora de 0..100% em FactH3Observation.$rhColumn."
    }
    $surface = ConvertTo-InvariantDouble $row.surface_temperature_c `
        'FactH3Observation.surface_temperature_c'
    $dewPoint = ConvertTo-InvariantDouble $row.dew_point_c `
        'FactH3Observation.dew_point_c'
    $margin = ConvertTo-InvariantDouble $row.dew_point_margin_c `
        'FactH3Observation.dew_point_margin_c'
    Assert-Close $margin ($surface - $dewPoint) 0.0011 `
        'FactH3Observation.dew_point_margin_c'
    foreach ($booleanColumn in @('door_open', 'hvac_active')) {
        $actual = ConvertTo-StrictBoolean $row.$booleanColumn `
            "FactH3Observation.$booleanColumn"
        $expected = ConvertTo-StrictBoolean $source.$booleanColumn `
            "H3.$booleanColumn"
        Assert-Condition ($actual -eq $expected) `
            "Booleano divergente entre fonte e fato em $booleanColumn[$key]."
    }
}
Assert-Condition ($H3FactByKey.Count -eq $H3SourceByKey.Count) `
    'Os conjuntos de chaves H3 da fonte e do fato não são biunívocos.'

$SourceHighRiskMinutes = ($H3Source | Where-Object {
    $_.risk_level -in @('High', 'Critical')
} | ForEach-Object {
    $CadenceMinutes
} | Measure-Object -Sum).Sum
$FactHighRiskMinutes = ($H3Observations | Where-Object {
    $_.risk_level -in @('High', 'Critical')
} | ForEach-Object {
    ConvertTo-InvariantDouble $_.interval_minutes 'FactH3Observation.interval_minutes'
} | Measure-Object -Sum).Sum
$SourceMinimumMargin = ($H3Source | ForEach-Object {
    ConvertTo-InvariantDouble $_.dew_point_margin_c 'H3.dew_point_margin_c'
} | Measure-Object -Minimum).Minimum
$FactMinimumMargin = ($H3Observations | ForEach-Object {
    ConvertTo-InvariantDouble $_.dew_point_margin_c 'FactH3Observation.dew_point_margin_c'
} | Measure-Object -Minimum).Minimum

Add-ReconciliationMetric 'h3_high_risk_hours' 'Horas em risco H3' `
    ([double]$FactHighRiskMinutes / 60.0) ([double]$SourceHighRiskMinutes / 60.0) `
    0.000000001 'h' $FactHighRiskMinutes 60 'uma observação sintética' `
    'risk_level em High ou Critical' `
    'Limiar experimental; simulação não comprova condensação nem falha em campo.'
Add-ReconciliationMetric 'h3_minimum_margin_c' 'Margem mínima H3' `
    $FactMinimumMargin $SourceMinimumMargin 0.000000001 '°C' `
    $null $null 'uma observação sintética' 'mínimo de dew_point_margin_c' `
    'Margem simulada; não substitui sensor calibrado nem inspeção de campo.'

# Experimentos H3: identidades pareadas e métricas por réplica/intervenção.
$H3ExperimentSource = @(Import-Csv -LiteralPath $H3ExperimentPath -Delimiter ';')
Assert-Condition ($H3ExperimentSource.Count -eq $H3Experiments.Count) `
    'A quantidade de experimentos H3 diverge da fonte.'
$ExperimentFields = @(
    'baseline_exposure_hours', 'intervention_exposure_hours', 'exposure_hours_avoided',
    'baseline_high_risk_events', 'intervention_high_risk_events', 'high_risk_events_avoided',
    'baseline_minimum_margin_c', 'intervention_minimum_margin_c', 'minimum_margin_gain_c'
)
$ExperimentSourceByKey = @{}
foreach ($row in $H3ExperimentSource) {
    Assert-Condition (ConvertTo-StrictBoolean $row.is_synthetic 'H3Experiment.is_synthetic') `
        'A fonte experimental H3 deve permanecer explicitamente sintética.'
    $key = "$($row.replication)|$($row.intervention_id)"
    Assert-Condition (-not $ExperimentSourceByKey.ContainsKey($key)) `
        "Chave experimental H3 duplicada: $key"
    $ExperimentSourceByKey[$key] = $row
}
$ExperimentFactByKey = @{}
foreach ($row in $H3Experiments) {
    $key = "$($row.replication)|$($row.intervention_id)"
    Assert-Condition ($ExperimentSourceByKey.ContainsKey($key)) `
        "Experimento H3 curado sem linha-fonte: $key"
    Assert-Condition (-not $ExperimentFactByKey.ContainsKey($key)) `
        "Chave experimental H3 duplicada no fato: $key"
    $ExperimentFactByKey[$key] = $row
    $source = $ExperimentSourceByKey[$key]
    Assert-Condition ([int]$row.seed -eq [int]$source.seed -and
        $row.evidence_class -eq 'synthetic') `
        "Metadados divergentes no experimento H3 $key."
    foreach ($field in $ExperimentFields) {
        $actual = ConvertTo-InvariantDouble $row.$field "FactH3Experiment.$field"
        $expected = ConvertTo-InvariantDouble $source.$field "H3Experiment.$field"
        Assert-Close $actual $expected 0.000000001 "FactH3Experiment.$field"
    }
    $baselineExposure = ConvertTo-InvariantDouble $row.baseline_exposure_hours 'baseline_exposure_hours'
    $interventionExposure = ConvertTo-InvariantDouble $row.intervention_exposure_hours 'intervention_exposure_hours'
    $avoidedExposure = ConvertTo-InvariantDouble $row.exposure_hours_avoided 'exposure_hours_avoided'
    Assert-Condition ($baselineExposure -ge 0 -and $interventionExposure -ge 0) `
        "Exposição negativa no experimento $key."
    Assert-Close $avoidedExposure ($baselineExposure - $interventionExposure) `
        0.000000001 "exposure_hours_avoided[$key]"
    $baselineEvents = ConvertTo-InvariantDouble $row.baseline_high_risk_events 'baseline_high_risk_events'
    $interventionEvents = ConvertTo-InvariantDouble $row.intervention_high_risk_events 'intervention_high_risk_events'
    $avoidedEvents = ConvertTo-InvariantDouble $row.high_risk_events_avoided 'high_risk_events_avoided'
    Assert-Condition ($baselineEvents -ge 0 -and $interventionEvents -ge 0 -and
        $baselineEvents % 1 -eq 0 -and $interventionEvents % 1 -eq 0) `
        "Contagem de eventos inválida no experimento $key."
    Assert-Close $avoidedEvents ($baselineEvents - $interventionEvents) `
        0.000000001 "high_risk_events_avoided[$key]"
    $baselineMargin = ConvertTo-InvariantDouble $row.baseline_minimum_margin_c 'baseline_minimum_margin_c'
    $interventionMargin = ConvertTo-InvariantDouble $row.intervention_minimum_margin_c 'intervention_minimum_margin_c'
    $marginGain = ConvertTo-InvariantDouble $row.minimum_margin_gain_c 'minimum_margin_gain_c'
    Assert-Close $marginGain ($interventionMargin - $baselineMargin) `
        0.000000001 "minimum_margin_gain_c[$key]"
}
Assert-Condition ($ExperimentFactByKey.Count -eq $ExperimentSourceByKey.Count) `
    'Os conjuntos de chaves experimentais da fonte e do fato não são biunívocos.'

$SourceExposureMean = ($H3ExperimentSource | ForEach-Object {
    ConvertTo-InvariantDouble $_.exposure_hours_avoided 'H3Experiment.exposure_hours_avoided'
} | Measure-Object -Average).Average
$FactExposureMean = ($H3Experiments | ForEach-Object {
    ConvertTo-InvariantDouble $_.exposure_hours_avoided 'FactH3Experiment.exposure_hours_avoided'
} | Measure-Object -Average).Average
$SourceAvoidedEvents = ($H3ExperimentSource | ForEach-Object {
    ConvertTo-InvariantDouble $_.high_risk_events_avoided 'H3Experiment.high_risk_events_avoided'
} | Measure-Object -Sum).Sum
$FactAvoidedEvents = ($H3Experiments | ForEach-Object {
    ConvertTo-InvariantDouble $_.high_risk_events_avoided 'FactH3Experiment.high_risk_events_avoided'
} | Measure-Object -Sum).Sum
$SourceMarginGainMean = ($H3ExperimentSource | ForEach-Object {
    ConvertTo-InvariantDouble $_.minimum_margin_gain_c 'H3Experiment.minimum_margin_gain_c'
} | Measure-Object -Average).Average
$FactMarginGainMean = ($H3Experiments | ForEach-Object {
    ConvertTo-InvariantDouble $_.minimum_margin_gain_c 'FactH3Experiment.minimum_margin_gain_c'
} | Measure-Object -Average).Average

Add-ReconciliationMetric 'h3_mean_exposure_avoided_hours' `
    'Diferença pareada média de exposição' $FactExposureMean $SourceExposureMean `
    0.000000001 'h/replication' $null $null 'uma réplica por intervenção' `
    'média de baseline_exposure_hours - intervention_exposure_hours' `
    'Diferença válida somente dentro do modelo sintético; não é efeito causal em campo.'
Add-ReconciliationMetric 'h3_avoided_high_risk_events' `
    'Eventos de alto risco evitados' $FactAvoidedEvents $SourceAvoidedEvents `
    0 'count' $null $null 'uma réplica por intervenção' `
    'soma de baseline_high_risk_events - intervention_high_risk_events' `
    'Contagem de eventos simulados; depende da frequência e da regra experimental.'
Add-ReconciliationMetric 'h3_mean_minimum_margin_gain_c' `
    'Ganho médio de margem mínima' $FactMarginGainMean $SourceMarginGainMean `
    0.000000001 '°C/replication' $null $null 'uma réplica por intervenção' `
    'média de intervention_minimum_margin_c - baseline_minimum_margin_c' `
    'Resultado do modelo sintético; não substitui ensaio de laboratório ou campo.'

# Simulador: coerência de unidades e reconciliação por cenário.
$FaultSource = @(Import-Csv -LiteralPath $FaultStudyPath)
Assert-Condition ($FaultSource.Count -eq $FaultStudies.Count) `
    'A quantidade de cenários diverge da fonte do estudo de falhas.'
$FaultSourceByScenario = @{}
foreach ($row in $FaultSource) {
    Assert-Condition (-not $FaultSourceByScenario.ContainsKey($row.scenario)) `
        "Cenário duplicado na fonte do estudo de falhas: $($row.scenario)"
    $FaultSourceByScenario[$row.scenario] = $row
}
$FaultFactByScenario = @{}
foreach ($row in $FaultStudies) {
    Assert-Condition ($FaultSourceByScenario.ContainsKey($row.scenario_id)) `
        "Cenário curado sem linha-fonte: $($row.scenario_id)"
    Assert-Condition (-not $FaultFactByScenario.ContainsKey($row.scenario_id)) `
        "Cenário duplicado no fato: $($row.scenario_id)"
    $FaultFactByScenario[$row.scenario_id] = $row
    $source = $FaultSourceByScenario[$row.scenario_id]
    $expectation = ConvertTo-StrictBoolean $row.expectation_met 'FactFaultStudy.expectation_met'
    $sourceExpectation = ConvertTo-StrictBoolean $source.expectationMet 'FaultStudy.expectationMet'
    Assert-Condition ($expectation -eq $sourceExpectation) `
        "Expectativa divergente no cenário $($row.scenario_id)."
    $expectedQuality = if ($expectation) { 'valid' } else { 'warning' }
    Assert-Condition ($row.quality_status -eq $expectedQuality) `
        "Qualidade incompatível com expectation_met no cenário $($row.scenario_id)."
    foreach ($mapping in @(
        @('simulated_seconds', 'simulatedSeconds'),
        @('final_physical_volume_liters', 'finalPhysicalVolumeLiters'),
        @('final_reported_volume_liters', 'finalReportedVolumeLiters'),
        @('maximum_sensor_deviation_liters', 'maximumSensorDeviationLiters'),
        @('valve_open_at_capacity_steps', 'valveOpenAtCapacitySteps'),
        @('valve_command_divergence_steps', 'valveCommandDivergenceSteps')
    )) {
        $actual = ConvertTo-InvariantDouble $row.($mapping[0]) "FactFaultStudy.$($mapping[0])"
        $expected = ConvertTo-InvariantDouble $source.($mapping[1]) "FaultStudy.$($mapping[1])"
        Assert-Condition ($actual -ge 0) `
            "Valor negativo em FactFaultStudy.$($mapping[0])."
        Assert-Close $actual $expected 0.000000001 "FactFaultStudy.$($mapping[0])"
    }
    foreach ($stepColumn in @('valve_open_at_capacity_steps', 'valve_command_divergence_steps')) {
        $steps = ConvertTo-InvariantDouble $row.$stepColumn "FactFaultStudy.$stepColumn"
        Assert-Condition ($steps % 1 -eq 0) `
            "Contagem não inteira em FactFaultStudy.$stepColumn."
    }
    $simulatedSeconds = ConvertTo-InvariantDouble $row.simulated_seconds 'simulated_seconds'
    $targetSeconds = ConvertTo-OptionalInvariantDouble $row.target_reached_at_seconds `
        'target_reached_at_seconds'
    if ($null -ne $targetSeconds) {
        Assert-Condition ($targetSeconds -ge 0 -and $targetSeconds -le $simulatedSeconds) `
            "Tempo-alvo fora do intervalo simulado no cenário $($row.scenario_id)."
        $sourceTarget = ConvertTo-OptionalInvariantDouble $source.targetReachedAtSeconds `
            'FaultStudy.targetReachedAtSeconds'
        Assert-Condition ($null -ne $sourceTarget) `
            "Tempo-alvo presente somente no fato para $($row.scenario_id)."
        Assert-Close $targetSeconds $sourceTarget 0.000000001 `
            "target_reached_at_seconds[$($row.scenario_id)]"
    }
    else {
        Assert-Condition ([string]::IsNullOrWhiteSpace($source.targetReachedAtSeconds)) `
            "Tempo-alvo ausente somente no fato para $($row.scenario_id)."
    }
    foreach ($booleanMapping in @(
        @('final_valve_command', 'finalValveCommand'),
        @('final_valve_effective_state', 'finalValveEffectiveState')
    )) {
        $actual = ConvertTo-StrictBoolean $row.($booleanMapping[0]) `
            "FactFaultStudy.$($booleanMapping[0])"
        $expected = ConvertTo-StrictBoolean $source.($booleanMapping[1]) `
            "FaultStudy.$($booleanMapping[1])"
        Assert-Condition ($actual -eq $expected) `
            "Estado booleano divergente no cenário $($row.scenario_id)."
    }
    Assert-Condition ($row.observation -eq $source.observation -and
        $row.evidence_class -eq 'synthetic') `
        "Observação ou classe de evidência divergente no cenário $($row.scenario_id)."
}
Assert-Condition ($FaultFactByScenario.Count -eq $FaultSourceByScenario.Count) `
    'Os conjuntos de cenários da fonte e do fato não são biunívocos.'

$FactExpectationCount = @($FaultStudies | Where-Object {
    ConvertTo-StrictBoolean $_.expectation_met 'FactFaultStudy.expectation_met'
}).Count
$SourceExpectationCount = @($FaultSource | Where-Object {
    ConvertTo-StrictBoolean $_.expectationMet 'FaultStudy.expectationMet'
}).Count
$FactDivergenceSteps = ($FaultStudies | ForEach-Object {
    ConvertTo-InvariantDouble $_.valve_command_divergence_steps `
        'FactFaultStudy.valve_command_divergence_steps'
} | Measure-Object -Sum).Sum
$SourceDivergenceSteps = ($FaultSource | ForEach-Object {
    ConvertTo-InvariantDouble $_.valveCommandDivergenceSteps `
        'FaultStudy.valveCommandDivergenceSteps'
} | Measure-Object -Sum).Sum
$FactMaximumDeviation = ($FaultStudies | ForEach-Object {
    ConvertTo-InvariantDouble $_.maximum_sensor_deviation_liters `
        'FactFaultStudy.maximum_sensor_deviation_liters'
} | Measure-Object -Maximum).Maximum
$SourceMaximumDeviation = ($FaultSource | ForEach-Object {
    ConvertTo-InvariantDouble $_.maximumSensorDeviationLiters `
        'FaultStudy.maximumSensorDeviationLiters'
} | Measure-Object -Maximum).Maximum

Add-ReconciliationMetric 'fault_expectation_ratio' 'Taxa de expectativa' `
    ([double]$FactExpectationCount / $FaultStudies.Count) `
    ([double]$SourceExpectationCount / $FaultSource.Count) 0.000000001 'ratio' `
    $FactExpectationCount $FaultStudies.Count 'um cenário por execução' `
    'expectation_met = true' `
    'Valida respostas esperadas do software; não valida PLC, rede ou hardware real.'
Add-ReconciliationMetric 'fault_divergence_steps' 'Passos de divergência comando/estado' `
    $FactDivergenceSteps $SourceDivergenceSteps 0 'count' `
    $null $null 'um cenário por execução' `
    'soma de valve_command_divergence_steps' `
    'Divergência sintética pode ser intencional no cenário de falha.'
Add-ReconciliationMetric 'fault_maximum_sensor_deviation_liters' `
    'Desvio máximo de sensor' $FactMaximumDeviation $SourceMaximumDeviation `
    0.000000001 'L' $null $null 'um cenário por execução' `
    'máximo de maximum_sensor_deviation_liters' `
    'Valor sintético; não representa calibração ou incerteza de instrumento real.'

$Report = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
    evidenceNotice = 'Todos os valores reconciliados são sintéticos e validam somente contratos e cálculos dos softwares.'
    sourceHashes = @($SourceRows | Where-Object { $_.source_key -ne 'unknown' } |
        ForEach-Object {
            [ordered]@{
                project_id = $_.project_id
                source_id = $_.source_id
                sha256 = $_.source_sha256
            }
        })
    summary = [ordered]@{
        reconciledMetrics = $Metrics.Count
        validMetrics = @($Metrics | Where-Object status -eq 'valid').Count
        factRows = $WorkOrders.Count + $H3Observations.Count +
            $H3Experiments.Count + $FaultStudies.Count
    }
    metrics = @($Metrics)
}
$ReportDirectory = Split-Path -Parent $ReportPath
if (-not [string]::IsNullOrWhiteSpace($ReportDirectory)) {
    New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
}
$Report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding utf8

Write-Host 'KPIs e unidades reconciliados com sucesso.' -ForegroundColor Green
Write-Host ("Métricas: {0}; fatos verificados: {1:N0}; relatório: {2}" -f `
    $Metrics.Count, $Report.summary.factRows, $ReportPath)
$Metrics | Select-Object metric_id, fact_value, source_value, unit, status |
    Format-Table -AutoSize
