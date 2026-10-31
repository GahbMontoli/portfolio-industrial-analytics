[CmdletBinding()]
param(
    [string]$DataDirectory,
    [string]$DaxPath,
    [string]$ContractPath,
    [string]$KpiReportPath
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

$ValidatorPath = Join-Path $PSScriptRoot 'Test-PortfolioBiMeasures.ps1'
$TempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).
    TrimEnd([System.IO.Path]::DirectorySeparatorChar)
$TempRoot = Join-Path $TempBase "portfolio-bi-measure-mutations-$([Guid]::NewGuid().ToString('N'))"
$ResolvedTempRoot = [System.IO.Path]::GetFullPath($TempRoot)
$comparison = if ([OperatingSystem]::IsWindows()) {
    [StringComparison]::OrdinalIgnoreCase
}
else {
    [StringComparison]::Ordinal
}
if (-not $ResolvedTempRoot.StartsWith(
    "$TempBase$([System.IO.Path]::DirectorySeparatorChar)",
    $comparison)) {
    throw "Diretório temporário fora da raiz esperada: $ResolvedTempRoot"
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [object]$Value
    )

    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding utf8
}

function New-MutationCase {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $caseRoot = Join-Path $ResolvedTempRoot $Name
    New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null
    $caseDax = Join-Path $caseRoot 'IndustrialMeasures.dax'
    $caseContract = Join-Path $caseRoot 'measure-contracts.json'
    $caseKpi = Join-Path $caseRoot 'kpi-reconciliation.json'
    Copy-Item -LiteralPath $DaxPath -Destination $caseDax
    Copy-Item -LiteralPath $KpiReportPath -Destination $caseKpi

    $contract = Get-Content -LiteralPath $ContractPath -Raw | ConvertFrom-Json
    $contract.reconciliationReport = [System.IO.Path]::GetRelativePath(
        $ProjectRoot,
        $caseKpi).Replace('\', '/')
    Write-JsonFile -Path $caseContract -Value $contract

    return [pscustomobject]@{
        Name = $Name
        Root = $caseRoot
        Dax = $caseDax
        Contract = $caseContract
        Kpi = $caseKpi
        Output = Join-Path $caseRoot 'measure-validation.json'
    }
}

function Invoke-CaseValidator {
    param(
        [Parameter(Mandatory)]
        [object]$Case
    )

    & $ValidatorPath `
        -DataDirectory $DataDirectory `
        -DaxPath $Case.Dax `
        -ContractPath $Case.Contract `
        -KpiReportPath $Case.Kpi `
        -OutputPath $Case.Output *> $null
}

$script:RejectedCount = 0
function Assert-MutationRejected {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [scriptblock]$Mutate,
        [Parameter(Mandatory)]
        [string]$ExpectedMessage
    )

    $case = New-MutationCase -Name $Name
    & $Mutate $case
    $failure = $null
    try {
        Invoke-CaseValidator -Case $case
    }
    catch {
        $failure = $_
    }

    if ($null -eq $failure) {
        throw "Mutação aceita indevidamente: $Name"
    }
    if ($failure.Exception.Message.IndexOf(
        $ExpectedMessage,
        [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "Mutação $Name falhou pelo motivo inesperado: $($failure.Exception.Message)"
    }
    $script:RejectedCount++
}

function Replace-DaxText {
    param(
        [Parameter(Mandatory)]
        [object]$Case,
        [Parameter(Mandatory)]
        [string]$Old,
        [Parameter(Mandatory)]
        [string]$New
    )

    $content = Get-Content -LiteralPath $Case.Dax -Raw
    if (-not $content.Contains($Old)) {
        throw "Trecho DAX da mutação não encontrado: $Old"
    }
    $content.Replace($Old, $New) |
        Set-Content -LiteralPath $Case.Dax -Encoding utf8
}

try {
    New-Item -ItemType Directory -Path $ResolvedTempRoot | Out-Null
    $baseline = New-MutationCase -Name 'baseline'
    Invoke-CaseValidator -Case $baseline

    Assert-MutationRejected -Name 'missing-column' -ExpectedMessage 'Coluna inexistente' -Mutate {
        param($case)
        Replace-DaxText $case "'FactH3Observation'[interval_minutes]" `
            "'FactH3Observation'[interval_hours]"
    }
    Assert-MutationRejected -Name 'unknown-table' -ExpectedMessage 'Tabela inexistente' -Mutate {
        param($case)
        Replace-DaxText $case "MAX('FactFaultStudy'[maximum_sensor_deviation_liters])" `
            "MAX('FactDataQuality'[maximum_sensor_deviation_liters])"
    }
    Assert-MutationRejected -Name 'missing-marker' -ExpectedMessage 'marcador' -Mutate {
        param($case)
        Replace-DaxText $case '// @metric-id work_orders_open' '// marker removed by mutation test'
    }
    Assert-MutationRejected -Name 'duplicate-measure' -ExpectedMessage 'duplicados' -Mutate {
        param($case)
        Replace-DaxText $case "MEASURE 'FactWorkOrder'[Ordens Encerradas] =" `
            "MEASURE 'FactWorkOrder'[Ordens Abertas] ="
    }
    Assert-MutationRejected -Name 'wrong-alias-target' -ExpectedMessage 'medida incorreta' -Mutate {
        param($case)
        Replace-DaxText $case '"work_orders_open", [Ordens Abertas]' `
            '"work_orders_open", [__mutation_temp]'
        Replace-DaxText $case '"work_orders_closed", [Ordens Encerradas]' `
            '"work_orders_closed", [Ordens Abertas]'
        Replace-DaxText $case '"work_orders_open", [__mutation_temp]' `
            '"work_orders_open", [Ordens Encerradas]'
    }
    Assert-MutationRejected -Name 'extra-row-output' -ExpectedMessage 'saídas adicionais' -Mutate {
        param($case)
        Replace-DaxText $case '"work_orders_open", [Ordens Abertas],' `
            "`"unexpected`", 42,`r`n        `"work_orders_open`", [Ordens Abertas],"
    }
    Assert-MutationRejected -Name 'unit-mismatch' -ExpectedMessage 'reconciliação' -Mutate {
        param($case)
        $contract = Get-Content -LiteralPath $case.Contract -Raw | ConvertFrom-Json
        $entry = $contract.measures | Where-Object metricId -eq 'closure_completeness_ratio'
        $entry.unit = 'count'
        $entry.formatString = '0'
        Write-JsonFile $case.Contract $contract
    }
    Assert-MutationRejected -Name 'dependency-mismatch' -ExpectedMessage 'dependências de coluna' -Mutate {
        param($case)
        $contract = Get-Content -LiteralPath $case.Contract -Raw | ConvertFrom-Json
        $entry = $contract.measures | Where-Object metricId -eq 'h3_minimum_margin_c'
        $entry.columnDependencies = @()
        Write-JsonFile $case.Contract $contract
    }
    Assert-MutationRejected -Name 'invalid-kpi-status' -ExpectedMessage 'status valid' -Mutate {
        param($case)
        $report = Get-Content -LiteralPath $case.Kpi -Raw | ConvertFrom-Json
        $report.metrics[0].status = 'warning'
        Write-JsonFile $case.Kpi $report
    }
    Assert-MutationRejected -Name 'contract-path-mismatch' -ExpectedMessage 'canonicalQuery' -Mutate {
        param($case)
        $contract = Get-Content -LiteralPath $case.Contract -Raw | ConvertFrom-Json
        $contract.canonicalQuery = 'OtherMeasures.dax'
        Write-JsonFile $case.Contract $contract
    }

    Write-Host 'Mutações do contrato DAX rejeitadas com sucesso.' -ForegroundColor Green
    Write-Host "Casos negativos: $RejectedCount; baseline válido: 1."
}
finally {
    if (Test-Path -LiteralPath $ResolvedTempRoot) {
        Remove-Item -LiteralPath $ResolvedTempRoot -Recurse -Force
    }
}
