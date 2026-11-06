[CmdletBinding()]
param(
    [string]$DataDirectory
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($DataDirectory)) {
    $DataDirectory = Join-Path $ProjectRoot 'data\curated'
}

$ValidatorPath = Join-Path $PSScriptRoot 'Test-PortfolioBiDataset.ps1'
$ResolvedDataDirectory = [System.IO.Path]::GetFullPath($DataDirectory)
foreach ($requiredPath in @(
        $ValidatorPath,
        (Join-Path $ResolvedDataDirectory 'manifest.json'))) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Artefato obrigatório ausente: $requiredPath"
    }
}

$TempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).
    TrimEnd([System.IO.Path]::DirectorySeparatorChar)
$TempRoot = Join-Path $TempBase `
    "portfolio-bi-dataset-provenance-mutations-$([Guid]::NewGuid().ToString('N'))"
$ResolvedTempRoot = [System.IO.Path]::GetFullPath($TempRoot)
$PathComparison = if ([OperatingSystem]::IsWindows()) {
    [StringComparison]::OrdinalIgnoreCase
}
else {
    [StringComparison]::Ordinal
}
$SafeTempPrefix = "$TempBase$([System.IO.Path]::DirectorySeparatorChar)"
if (-not $ResolvedTempRoot.StartsWith($SafeTempPrefix, $PathComparison)) {
    throw "Diretório temporário fora da raiz esperada: $ResolvedTempRoot"
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [object]$Value
    )

    $Value | ConvertTo-Json -Depth 12 |
        Set-Content -LiteralPath $Path -Encoding utf8
}

function New-MutationCase {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $caseRoot = Join-Path $ResolvedTempRoot $Name
    New-Item -ItemType Directory -Path $caseRoot | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $ResolvedDataDirectory -Force)) {
        Copy-Item -LiteralPath $item.FullName -Destination $caseRoot -Recurse
    }

    return [pscustomobject]@{
        Name = $Name
        Root = $caseRoot
        Manifest = Join-Path $caseRoot 'manifest.json'
    }
}

function Invoke-CaseValidator {
    param(
        [Parameter(Mandatory)]
        [object]$Case
    )

    & $ValidatorPath -DataDirectory $Case.Root *> $null
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
    $manifest = Get-Content -LiteralPath $case.Manifest -Raw | ConvertFrom-Json
    & $Mutate $manifest
    Write-JsonFile -Path $case.Manifest -Value $manifest

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

try {
    New-Item -ItemType Directory -Path $ResolvedTempRoot | Out-Null
    $baseline = New-MutationCase -Name 'baseline'
    Invoke-CaseValidator -Case $baseline

    Assert-MutationRejected -Name 'source-lock-hash-mismatch' `
        -ExpectedMessage 'Hash divergente para o source lock' -Mutate {
            param($manifest)
            $manifest.sourceLock.sha256 = '0' * 64
        }
    Assert-MutationRejected -Name 'source-commit-mismatch' `
        -ExpectedMessage 'Campo commitSha divergente' -Mutate {
            param($manifest)
            $manifest.sources[0].commitSha = '0' * 40
        }
    Assert-MutationRejected -Name 'extra-source' `
        -ExpectedMessage 'Fonte do manifesto ausente no source lock' -Mutate {
            param($manifest)
            $extra = $manifest.sources[0] | ConvertTo-Json -Depth 5 | ConvertFrom-Json
            $extra.path = 'h3-monitor/output/validation/unexpected-extra.csv'
            $manifest.sources = @($manifest.sources) + $extra
        }
    Assert-MutationRejected -Name 'missing-source' `
        -ExpectedMessage 'Conjunto divergente' -Mutate {
            param($manifest)
            $manifest.sources = @($manifest.sources | Select-Object -SkipLast 1)
        }
    Assert-MutationRejected -Name 'validation-report-traversal' `
        -ExpectedMessage 'Nome inválido para o relatório' -Mutate {
            param($manifest)
            $manifest.sourceLock.validationReport = '../source-lock-validation.json'
        }

    Write-Host 'Mutações de proveniência do dataset rejeitadas com sucesso.' `
        -ForegroundColor Green
    Write-Host "Casos negativos: $RejectedCount; baseline válido: 1."
}
finally {
    if (Test-Path -LiteralPath $ResolvedTempRoot) {
        $cleanupPath = [System.IO.Path]::GetFullPath($ResolvedTempRoot)
        if (-not $cleanupPath.StartsWith($SafeTempPrefix, $PathComparison)) {
            throw "Limpeza recusada fora da raiz temporária: $cleanupPath"
        }
        Remove-Item -LiteralPath $cleanupPath -Recurse -Force
    }
}
