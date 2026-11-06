[CmdletBinding()]
param(
    [string]$DataDirectory
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$WorkspaceRoot = Split-Path -Parent $ProjectRoot
if ([string]::IsNullOrWhiteSpace($DataDirectory)) {
    $DataDirectory = Join-Path $ProjectRoot 'data\curated'
}

$ExpectedTables = [ordered]@{
    dim_project = 'project_id'
    dim_asset = 'asset_id'
    dim_date = 'date_key'
    dim_evidence = 'evidence_key'
    dim_source = 'source_key'
    fact_work_order = 'work_order_id'
    bridge_work_order_check = 'check_text'
    bridge_work_order_part = 'part_text'
    fact_h3_observation = 'observed_at_utc'
    fact_h3_experiment = 'intervention_id'
    fact_fault_study = 'scenario_id'
}
$AllowedEvidenceClasses = @(
    'synthetic', 'official_raw', 'lab_observed', 'field_observed', 'derived'
)
$AllowedQualityStatuses = @('valid', 'warning', 'rejected', 'raw_unvalidated')
$CuratedQualityStatuses = @('valid', 'warning')
$RequiredQualityLimitFragments = @{
    valid = 'critérios automatizados'
    warning = 'usar com ressalva'
    rejected = 'não usar em análises'
    raw_unvalidated = 'não usar antes da validação'
}
$MonthNames = @(
    'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
    'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'
)
$DayNames = @(
    'segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira',
    'sexta-feira', 'sábado', 'domingo'
)

function Assert-PortablePath {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Context
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or
        [System.IO.Path]::IsPathRooted($Path) -or
        $Path -match '^[A-Za-z]:' -or
        $Path.Contains('\') -or
        @($Path.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0) {
        throw "Caminho não portável em ${Context}: $Path"
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

    $actualValues = @($Actual | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $expectedValues = @($Expected | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    if ($actualValues.Count -ne $expectedValues.Count -or
        ($actualValues -join "`n") -cne ($expectedValues -join "`n")) {
        throw "Conjunto divergente em ${Context}."
    }
}

function Get-UtcDateKey {
    param(
        [Parameter(Mandatory)]
        [string]$Timestamp,
        [Parameter(Mandatory)]
        [string]$Context
    )

    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($Timestamp, [ref]$parsed)) {
        throw "Timestamp inválido em ${Context}: $Timestamp"
    }
    return $parsed.ToUniversalTime().ToString(
        'yyyyMMdd',
        [System.Globalization.CultureInfo]::InvariantCulture)
}

$ManifestPath = Join-Path $DataDirectory 'manifest.json'
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Manifesto ausente: $ManifestPath"
}
$Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($Manifest.schemaVersion -ne 2) {
    throw "Versão de manifesto não suportada: $($Manifest.schemaVersion)"
}
if ([string]::IsNullOrWhiteSpace($Manifest.evidenceNotice)) {
    throw 'O manifesto não documenta o limite das evidências.'
}

$ExpectedSourceLockPath = [System.IO.Path]::GetRelativePath(
    $WorkspaceRoot,
    (Join-Path $ProjectRoot 'config\source-lock.json')).Replace('\', '/')
if ($null -eq $Manifest.sourceLock) {
    throw 'O manifesto não referencia o source lock.'
}
Assert-PortablePath -Path $Manifest.sourceLock.path -Context 'manifest.sourceLock.path'
if ($Manifest.sourceLock.path -cne $ExpectedSourceLockPath) {
    throw "Source lock inesperado no manifesto: $($Manifest.sourceLock.path)"
}
if ($Manifest.sourceLock.sha256 -cnotmatch '^[0-9a-f]{64}$') {
    throw 'SHA-256 inválido para o source lock do manifesto.'
}
$SourceLockPath = Join-Path $WorkspaceRoot $Manifest.sourceLock.path
if (-not (Test-Path -LiteralPath $SourceLockPath -PathType Leaf)) {
    throw "Source lock declarado no manifesto não encontrado: $($Manifest.sourceLock.path)"
}
$ActualSourceLockHash = (Get-FileHash -LiteralPath $SourceLockPath -Algorithm SHA256).
    Hash.ToLowerInvariant()
if ($ActualSourceLockHash -cne $Manifest.sourceLock.sha256) {
    throw 'Hash divergente para o source lock declarado no manifesto.'
}
$SourceLock = Get-Content -LiteralPath $SourceLockPath -Raw | ConvertFrom-Json
if ($SourceLock.schemaVersion -ne 1 -or $SourceLock.kind -ne 'portfolio-source-lock') {
    throw 'Source lock incompatível com o manifesto.'
}
$LockedRepositories = @($SourceLock.repositories)
$LockedArtifacts = @($SourceLock.artifacts)
if ($LockedRepositories.Count -ne 3 -or $LockedArtifacts.Count -ne 10) {
    throw 'O source lock deve declarar exatamente três repositórios e dez artefatos.'
}
$LockedRepositoryByProject = @{}
foreach ($repository in $LockedRepositories) {
    if ($LockedRepositoryByProject.ContainsKey([string]$repository.projectId)) {
        throw "Projeto duplicado no source lock: $($repository.projectId)"
    }
    $LockedRepositoryByProject[[string]$repository.projectId] = $repository
}
$LockedArtifactByPath = @{}
foreach ($artifact in $LockedArtifacts) {
    if ($LockedArtifactByPath.ContainsKey([string]$artifact.path)) {
        throw "Artefato duplicado no source lock: $($artifact.path)"
    }
    $LockedArtifactByPath[[string]$artifact.path] = $artifact
}

$ManifestTableNames = @($Manifest.tables.PSObject.Properties.Name)
if ($ManifestTableNames.Count -ne $ExpectedTables.Count) {
    throw "O manifesto deve declarar exatamente $($ExpectedTables.Count) tabelas."
}
foreach ($tableName in $ExpectedTables.Keys) {
    if ($ManifestTableNames -notcontains $tableName) {
        throw "Tabela não declarada no manifesto: $tableName"
    }
}

$ManifestSources = @($Manifest.sources)
$ManifestSourcePaths = @()
foreach ($source in $ManifestSources) {
    Assert-PortablePath -Path $source.path -Context 'manifest.sources.path'
    if ($source.sha256 -notmatch '^[0-9a-f]{64}$') {
        throw "SHA-256 inválido no manifesto para $($source.path)."
    }
    if (-not $LockedArtifactByPath.ContainsKey([string]$source.path)) {
        throw "Fonte do manifesto ausente no source lock: $($source.path)"
    }
    $lockedArtifact = $LockedArtifactByPath[[string]$source.path]
    if (-not $LockedRepositoryByProject.ContainsKey([string]$lockedArtifact.projectId)) {
        throw "Projeto ausente no source lock para $($source.path)."
    }
    $lockedRepository = $LockedRepositoryByProject[[string]$lockedArtifact.projectId]
    $ExpectedFields = [ordered]@{
        projectId = [string]$lockedArtifact.projectId
        repositoryUrl = [string]$lockedRepository.repositoryUrl
        commitSha = [string]$lockedRepository.commitSha
        path = [string]$lockedArtifact.path
        role = [string]$lockedArtifact.role
        sha256 = [string]$lockedArtifact.sha256
        evidenceClass = [string]$lockedArtifact.evidenceClass
        verificationMethod = [string]$lockedArtifact.verificationMethod
    }
    foreach ($field in $ExpectedFields.Keys) {
        if ([string]$source.$field -cne $ExpectedFields[$field]) {
            throw "Campo $field divergente entre manifesto e source lock para $($source.path)."
        }
    }
    $ManifestSourcePaths += $source.path
    $resolvedSourcePath = Join-Path $WorkspaceRoot $source.path
    if (-not (Test-Path -LiteralPath $resolvedSourcePath -PathType Leaf)) {
        throw "Fonte declarada no manifesto não encontrada: $($source.path)"
    }
    $actualHash = (Get-FileHash -LiteralPath $resolvedSourcePath -Algorithm SHA256).
        Hash.ToLowerInvariant()
    if ($actualHash -ne $source.sha256) {
        throw "Hash divergente para a fonte declarada no manifesto: $($source.path)"
    }
}
if (@($ManifestSourcePaths | Sort-Object -Unique).Count -ne $ManifestSourcePaths.Count) {
    throw 'O manifesto contém fontes duplicadas.'
}
Assert-SameSet -Actual $ManifestSourcePaths -Expected @($LockedArtifacts.path) `
    -Context 'fontes do manifesto versus source lock'

$ValidationReportName = [string]$Manifest.sourceLock.validationReport
if ([string]::IsNullOrWhiteSpace($ValidationReportName) -or
    $ValidationReportName -cne [System.IO.Path]::GetFileName($ValidationReportName) -or
    $ValidationReportName -match '[\\/]') {
    throw 'Nome inválido para o relatório de validação do source lock.'
}
$SourceLockValidationPath = Join-Path $DataDirectory $ValidationReportName
& (Join-Path $PSScriptRoot 'Test-PortfolioBiSourceLock.ps1') `
    -LockPath $SourceLockPath `
    -OutputPath $SourceLockValidationPath `
    -ExpectedArtifactPaths $ManifestSourcePaths
$SourceLockValidation = Get-Content -LiteralPath $SourceLockValidationPath -Raw |
    ConvertFrom-Json
if ($SourceLockValidation.schemaVersion -ne 1 -or
    $SourceLockValidation.status -ne 'valid' -or
    $SourceLockValidation.lock.sha256 -cne $Manifest.sourceLock.sha256) {
    throw 'Relatório de validação do source lock incompatível com o manifesto.'
}
Assert-SameSet -Actual @($SourceLockValidation.repositories.project_id) `
    -Expected @($LockedRepositories.projectId) `
    -Context 'repositórios do relatório versus source lock'
Assert-SameSet -Actual @($SourceLockValidation.artifacts.path) `
    -Expected @($LockedArtifacts.path) `
    -Context 'artefatos do relatório versus source lock'
if (@($SourceLockValidation.repositories | Where-Object status -ne 'valid').Count -gt 0 -or
    @($SourceLockValidation.artifacts | Where-Object status -ne 'valid').Count -gt 0) {
    throw 'O relatório do source lock contém item não validado.'
}

$Tables = @{}
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
    $Tables[$entry.Key] = $rows
}

$Projects = @($Tables.dim_project)
if (@($Projects.project_id | Sort-Object -Unique).Count -ne 3 -or
    @($Projects.project_id | Sort-Object -Unique).Count -ne $Projects.Count) {
    throw 'A dimensão de projetos deve conter os três sistemas sem chaves duplicadas.'
}
$ProjectIds = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@($Projects.project_id))

$DateRows = @($Tables.dim_date)
$DateKeys = @($DateRows.date_key)
$DateValues = @($DateRows.date)
if (@($DateKeys | Sort-Object -Unique).Count -ne $DateRows.Count -or
    @($DateValues | Sort-Object -Unique).Count -ne $DateRows.Count) {
    throw 'DimDate contém chave ou data duplicada.'
}
$ParsedDates = [System.Collections.Generic.List[DateTime]]::new()
for ($index = 0; $index -lt $DateRows.Count; $index++) {
    $row = $DateRows[$index]
    $date = [DateTime]::MinValue
    if (-not [DateTime]::TryParseExact(
            $row.date,
            'yyyy-MM-dd',
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None,
            [ref]$date)) {
        throw "Data inválida em DimDate: $($row.date)"
    }
    $ParsedDates.Add($date)
    $expectedDateKey = $date.ToString(
        'yyyyMMdd',
        [System.Globalization.CultureInfo]::InvariantCulture)
    $dayOfWeekNumber = (([int]$date.DayOfWeek + 6) % 7) + 1
    $quarterNumber = [int][Math]::Ceiling($date.Month / 3.0)
    $expectedWeekday = $dayOfWeekNumber -le 5
    if ($row.date_key -ne $expectedDateKey -or
        [int]$row.calendar_year -ne $date.Year -or
        [int]$row.quarter_number -ne $quarterNumber -or
        $row.quarter_label -ne "T$quarterNumber" -or
        [int]$row.month_number -ne $date.Month -or
        $row.month_name -ne $MonthNames[$date.Month - 1] -or
        $row.year_month_key -ne $date.ToString('yyyyMM') -or
        $row.year_month -ne $date.ToString('yyyy-MM') -or
        [int]$row.iso_year -ne [System.Globalization.ISOWeek]::GetYear($date) -or
        [int]$row.iso_week_number -ne [System.Globalization.ISOWeek]::GetWeekOfYear($date) -or
        [int]$row.day_of_month -ne $date.Day -or
        [int]$row.day_of_week_number -ne $dayOfWeekNumber -or
        $row.day_name -ne $DayNames[$dayOfWeekNumber - 1] -or
        [bool]::Parse($row.is_weekday) -ne $expectedWeekday -or
        [bool]::Parse($row.is_weekend) -eq $expectedWeekday) {
        throw "Atributos divergentes em DimDate para $($row.date)."
    }
    if ($index -gt 0 -and $date -ne $ParsedDates[$index - 1].AddDays(1)) {
        throw "DimDate não é contígua em $($row.date)."
    }
}
if ($ParsedDates[0].Month -ne 1 -or $ParsedDates[0].Day -ne 1 -or
    $ParsedDates[$ParsedDates.Count - 1].Month -ne 12 -or
    $ParsedDates[$ParsedDates.Count - 1].Day -ne 31) {
    throw 'DimDate deve cobrir anos-calendário completos.'
}
$DateKeySet = [System.Collections.Generic.HashSet[string]]::new([string[]]$DateKeys)

$EvidenceRows = @($Tables.dim_evidence)
if ($EvidenceRows.Count -ne 21 -or
    @($EvidenceRows.evidence_key | Sort-Object -Unique).Count -ne $EvidenceRows.Count) {
    throw 'DimEvidence deve conter 20 combinações e um membro Unknown, sem duplicatas.'
}
$EvidenceByKey = @{}
$ActualEvidenceCombinations = [System.Collections.Generic.HashSet[string]]::new()
foreach ($row in $EvidenceRows) {
    $EvidenceByKey[$row.evidence_key] = $row
    if ([string]::IsNullOrWhiteSpace($row.interpretation_limit)) {
        throw "Limite interpretativo ausente em DimEvidence: $($row.evidence_key)"
    }
    if ($row.evidence_key -eq 'unknown') {
        if ($row.evidence_class -ne 'unknown' -or
            $row.quality_status -ne 'unknown' -or
            -not [bool]::Parse($row.is_unknown)) {
            throw 'Membro Unknown inválido em DimEvidence.'
        }
        continue
    }
    if ($AllowedEvidenceClasses -notcontains $row.evidence_class -or
        $AllowedQualityStatuses -notcontains $row.quality_status -or
        $row.evidence_key -ne "$($row.evidence_class)|$($row.quality_status)" -or
        [bool]::Parse($row.is_unknown) -or
        [string]::IsNullOrWhiteSpace($row.class_label) -or
        [string]::IsNullOrWhiteSpace($row.quality_label) -or
        $row.interpretation_limit -notlike
            "*$($RequiredQualityLimitFragments[$row.quality_status])*" ) {
        throw "Membro inválido em DimEvidence: $($row.evidence_key)"
    }
    [void]$ActualEvidenceCombinations.Add($row.evidence_key)
}
foreach ($evidenceClass in $AllowedEvidenceClasses) {
    foreach ($qualityStatus in $AllowedQualityStatuses) {
        if (-not $ActualEvidenceCombinations.Contains("$evidenceClass|$qualityStatus")) {
            throw "Combinação ausente em DimEvidence: $evidenceClass|$qualityStatus"
        }
    }
}

$SourceRows = @($Tables.dim_source)
if ($SourceRows.Count -ne 5 -or
    @($SourceRows.source_key | Sort-Object -Unique).Count -ne $SourceRows.Count) {
    throw 'DimSource deve conter quatro fontes versionadas e um membro Unknown, sem duplicatas.'
}
$SourceByKey = @{}
$SourceNaturalKeys = @()
foreach ($row in $SourceRows) {
    $SourceByKey[$row.source_key] = $row
    Assert-PortablePath -Path $row.source_locator -Context "DimSource[$($row.source_key)]"
    if ($row.source_key -eq 'unknown') {
        if ($row.project_id -ne 'unknown' -or
            $row.source_id -ne 'unknown' -or
            $row.source_kind -ne 'unknown' -or
            $row.source_uri -ne 'urn:gahbmontoli:portfolio:source:unknown' -or
            $row.source_locator -ne 'unknown' -or
            -not [string]::IsNullOrWhiteSpace($row.source_sha256) -or
            $row.source_version -ne 'unknown' -or
            [int]$row.schema_version -ne 1 -or
            $row.evidence_class -ne 'unknown' -or
            $row.license_status -ne 'not_evaluated' -or
            [string]::IsNullOrWhiteSpace($row.interpretation_limit) -or
            -not [bool]::Parse($row.is_unknown)) {
            throw 'Membro Unknown inválido em DimSource.'
        }
        continue
    }
    if ($row.source_sha256 -notmatch '^[0-9a-f]{64}$' -or
        $row.source_key -ne "$($row.project_id)|$($row.source_id)|$($row.source_sha256)" -or
        $row.source_version -ne "sha256:$($row.source_sha256)" -or
        -not $ProjectIds.Contains($row.project_id) -or
        [string]::IsNullOrWhiteSpace($row.source_kind) -or
        $row.source_uri -notmatch '^urn:' -or
        [string]::IsNullOrWhiteSpace($row.license_status) -or
        [string]::IsNullOrWhiteSpace($row.interpretation_limit) -or
        $AllowedEvidenceClasses -notcontains $row.evidence_class -or
        [bool]::Parse($row.is_unknown)) {
        throw "Membro inválido em DimSource: $($row.source_key)"
    }
    $resolvedSourcePath = Join-Path $WorkspaceRoot $row.source_locator
    if (-not (Test-Path -LiteralPath $resolvedSourcePath -PathType Leaf)) {
        throw "Fonte versionada ausente: $($row.source_locator)"
    }
    $actualHash = (Get-FileHash -LiteralPath $resolvedSourcePath -Algorithm SHA256).
        Hash.ToLowerInvariant()
    if ($actualHash -ne $row.source_sha256) {
        throw "Hash divergente em DimSource: $($row.source_locator)"
    }
    $SourceNaturalKeys += "$($row.project_id)|$($row.source_id)|$($row.source_sha256)"
}
if (@($SourceNaturalKeys | Sort-Object -Unique).Count -ne $SourceNaturalKeys.Count) {
    throw 'DimSource contém versões naturais duplicadas.'
}

$Facts = [ordered]@{
    fact_work_order = 'work_order_opened_at_utc'
    fact_h3_observation = 'simulation_timestamp_utc'
    fact_h3_experiment = 'source_file_last_write_utc_proxy'
    fact_fault_study = 'package_exported_at_utc'
}
foreach ($entry in $Facts.GetEnumerator()) {
    foreach ($row in @($Tables[$entry.Key])) {
        if ([string]::IsNullOrWhiteSpace($row.project_id) -or
            [string]::IsNullOrWhiteSpace($row.run_id) -or
            [string]::IsNullOrWhiteSpace($row.source_id) -or
            -not $ProjectIds.Contains($row.project_id) -or
            $AllowedEvidenceClasses -notcontains $row.evidence_class -or
            $CuratedQualityStatuses -notcontains $row.quality_status -or
            $row.evidence_key -ne "$($row.evidence_class)|$($row.quality_status)" -or
            -not $EvidenceByKey.ContainsKey($row.evidence_key) -or
            -not $SourceByKey.ContainsKey($row.source_key) -or
            $row.observed_time_basis -ne $entry.Value) {
            throw "Envelope analítico inválido em $($entry.Key)."
        }
        $source = $SourceByKey[$row.source_key]
        if ($source.project_id -ne $row.project_id -or
            $source.source_id -ne $row.source_id -or
            $source.evidence_class -ne $row.evidence_class) {
            throw "Fonte incompatível com o fato em $($entry.Key)."
        }
        $expectedDateKey = Get-UtcDateKey `
            -Timestamp $row.observed_at_utc -Context $entry.Key
        if ($row.observed_date_key -ne $expectedDateKey -or
            -not $DateKeySet.Contains($row.observed_date_key)) {
            throw "Chave de data observada inválida em $($entry.Key)."
        }
    }
}

$WorkOrderRows = @($Tables.fact_work_order)
foreach ($row in $WorkOrderRows) {
    $expectedOpenedDateKey = Get-UtcDateKey `
        -Timestamp $row.opened_at_utc -Context 'fact_work_order.opened_at_utc'
    $observed = [DateTimeOffset]::Parse($row.observed_at_utc).ToUniversalTime()
    $opened = [DateTimeOffset]::Parse($row.opened_at_utc).ToUniversalTime()
    if ($row.opened_date_key -ne $expectedOpenedDateKey -or
        $row.observed_date_key -ne $row.opened_date_key -or
        $observed -ne $opened) {
        throw "Chave de abertura inválida na ordem $($row.work_order_id)."
    }
    if ([string]::IsNullOrWhiteSpace($row.closed_at_utc)) {
        if (-not [string]::IsNullOrWhiteSpace($row.closed_date_key)) {
            throw "Ordem aberta possui closed_date_key: $($row.work_order_id)."
        }
    }
    else {
        $expectedClosedDateKey = Get-UtcDateKey `
            -Timestamp $row.closed_at_utc -Context 'fact_work_order.closed_at_utc'
        if ($row.closed_date_key -ne $expectedClosedDateKey -or
            -not $DateKeySet.Contains($row.closed_date_key)) {
            throw "Chave de encerramento inválida na ordem $($row.work_order_id)."
        }
    }
}

foreach ($file in @('bridge_work_order_check', 'bridge_work_order_part')) {
    foreach ($row in @($Tables[$file])) {
        if ([string]::IsNullOrWhiteSpace($row.project_id) -or
            [string]::IsNullOrWhiteSpace($row.run_id) -or
            [string]::IsNullOrWhiteSpace($row.work_order_id) -or
            $row.evidence_key -ne "$($row.evidence_class)|$($row.quality_status)" -or
            -not $EvidenceByKey.ContainsKey($row.evidence_key) -or
            -not $SourceByKey.ContainsKey($row.source_key)) {
            throw "Ponte CMMS inválida em $file."
        }
        $source = $SourceByKey[$row.source_key]
        if ($source.project_id -ne $row.project_id -or
            $source.source_id -ne $row.source_id -or
            $source.evidence_class -ne $row.evidence_class) {
            throw "Fonte incompatível com a ponte em $file."
        }
    }
}

$AssetRows = @($Tables.dim_asset)
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
foreach ($file in @('bridge_work_order_check', 'bridge_work_order_part')) {
    $CmmsRows += @($Tables[$file])
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
foreach ($file in @('bridge_work_order_check', 'bridge_work_order_part')) {
    $bridgeRows = @($Tables[$file])
    $BridgeKeys = @($bridgeRows | ForEach-Object {
        "$($_.work_order_id)`u{001f}$($_.ordinal)"
    })
    if (@($BridgeKeys | Sort-Object -Unique).Count -ne $bridgeRows.Count) {
        throw "A ponte $file contém chave composta duplicada."
    }
    foreach ($row in $bridgeRows) {
        if (-not $WorkOrderIds.Contains($row.work_order_id)) {
            throw "Ponte $file referencia ordem inexistente: $($row.work_order_id)."
        }
    }
}

$PowerQueryFiles = [ordered]@{
    dim_project = 'DimProject.pq'
    dim_asset = 'DimAsset.pq'
    dim_date = 'DimDate.pq'
    dim_evidence = 'DimEvidence.pq'
    dim_source = 'DimSource.pq'
    fact_work_order = 'FactWorkOrder.pq'
    bridge_work_order_check = 'BridgeWorkOrderCheck.pq'
    bridge_work_order_part = 'BridgeWorkOrderPart.pq'
    fact_h3_observation = 'FactH3Observation.pq'
    fact_h3_experiment = 'FactH3Experiment.pq'
    fact_fault_study = 'FactFaultStudy.pq'
}
foreach ($entry in $PowerQueryFiles.GetEnumerator()) {
    $queryPath = Join-Path $ProjectRoot "power-query\$($entry.Value)"
    if (-not (Test-Path -LiteralPath $queryPath -PathType Leaf)) {
        throw "Consulta Power Query ausente: $($entry.Value)"
    }
    $query = Get-Content -LiteralPath $queryPath -Raw
    if (-not $query.Contains("\\$($entry.Key).csv")) {
        throw "Consulta $($entry.Value) não referencia $($entry.Key).csv."
    }
    foreach ($column in $Tables[$entry.Key][0].PSObject.Properties.Name) {
        if (-not $query.Contains("{`"$column`"")) {
            throw "Consulta $($entry.Value) não tipa a coluna $column."
        }
    }
}

$FactCount = ($Facts.Keys | ForEach-Object {
    @($Tables[$_]).Count
} | Measure-Object -Sum).Sum
Write-Host 'Pacote Power BI validado com sucesso.' -ForegroundColor Green
Write-Host ("Tabelas: {0}; fatos: {1:N0} linhas" -f $ExpectedTables.Count, $FactCount)
