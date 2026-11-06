[CmdletBinding()]
param(
    [string]$LockPath,
    [string]$H3Root,
    [string]$SimulatorRoot,
    [string]$CmmsRoot
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$WorkspaceRoot = Split-Path -Parent $ProjectRoot
if ([string]::IsNullOrWhiteSpace($LockPath)) {
    $LockPath = Join-Path $ProjectRoot 'config\source-lock.json'
}
if ([string]::IsNullOrWhiteSpace($H3Root)) {
    $H3Root = Join-Path $WorkspaceRoot 'h3-monitor'
}
if ([string]::IsNullOrWhiteSpace($SimulatorRoot)) {
    $SimulatorRoot = Join-Path $WorkspaceRoot 'simulador-industrial'
}
if ([string]::IsNullOrWhiteSpace($CmmsRoot)) {
    $CmmsRoot = Join-Path $WorkspaceRoot 'assistente-patinho'
}

$ValidatorPath = Join-Path $PSScriptRoot 'Test-PortfolioBiSourceLock.ps1'
foreach ($requiredPath in @($LockPath, $ValidatorPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Artefato obrigatório ausente: $requiredPath"
    }
}

$OriginalLock = Get-Content -LiteralPath $LockPath -Raw | ConvertFrom-Json
$ExpectedArtifactPaths = @($OriginalLock.artifacts.path)
$TempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).
    TrimEnd([System.IO.Path]::DirectorySeparatorChar)
$TempRoot = Join-Path $TempBase "portfolio-bi-source-lock-mutations-$([Guid]::NewGuid().ToString('N'))"
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
    $caseLock = Join-Path $caseRoot 'source-lock.json'
    Copy-Item -LiteralPath $LockPath -Destination $caseLock
    return [pscustomobject]@{
        Name = $Name
        Root = $caseRoot
        Lock = $caseLock
        Output = Join-Path $caseRoot 'source-lock-validation.json'
    }
}

function Invoke-CaseValidator {
    param(
        [Parameter(Mandatory)]
        [object]$Case,
        [switch]$SkipExpectedArtifactPaths
    )

    $validatorArguments = @{
        LockPath = $Case.Lock
        H3Root = $H3Root
        SimulatorRoot = $SimulatorRoot
        CmmsRoot = $CmmsRoot
        OutputPath = $Case.Output
    }
    if (-not $SkipExpectedArtifactPaths) {
        $validatorArguments.ExpectedArtifactPaths = $ExpectedArtifactPaths
    }
    & $ValidatorPath @validatorArguments *> $null
}

$script:RejectedCount = 0
function Assert-MutationRejected {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [scriptblock]$Mutate,
        [Parameter(Mandatory)]
        [string]$ExpectedMessage,
        [switch]$SkipExpectedArtifactPaths
    )

    $case = New-MutationCase -Name $Name
    $lock = Get-Content -LiteralPath $case.Lock -Raw | ConvertFrom-Json
    & $Mutate $lock
    Write-JsonFile -Path $case.Lock -Value $lock

    $failure = $null
    try {
        Invoke-CaseValidator -Case $case `
            -SkipExpectedArtifactPaths:$SkipExpectedArtifactPaths
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

    Assert-MutationRejected -Name 'artifact-hash-mismatch' `
        -ExpectedMessage 'Hash divergente' -Mutate {
            param($lock)
            $lock.artifacts[0].sha256 = '0' * 64
        }
    Assert-MutationRejected -Name 'unsafe-artifact-path' `
        -ExpectedMessage 'Caminho não portável' `
        -SkipExpectedArtifactPaths -Mutate {
            param($lock)
            $lock.artifacts[0].path = '../h3-monitor/output/validation/h3-synthetic.csv'
        }
    Assert-MutationRejected -Name 'invalid-commit' `
        -ExpectedMessage 'Commit SHA inválido' -Mutate {
            param($lock)
            $lock.repositories[0].commitSha = 'abc123'
        }
    Assert-MutationRejected -Name 'invalid-repository-url' `
        -ExpectedMessage 'URL pública inválida' -Mutate {
            param($lock)
            $lock.repositories[0].repositoryUrl = 'https://example.com/GahbMontoli/h3.git'
        }
    Assert-MutationRejected -Name 'origin-mismatch' `
        -ExpectedMessage 'Origin divergente' -Mutate {
            param($lock)
            $lock.repositories[0].repositoryUrl = 'https://github.com/GahbMontoli/outro-repositorio.git'
        }
    Assert-MutationRejected -Name 'invalid-evidence-class' `
        -ExpectedMessage 'Classe de evidência inválida' -Mutate {
            param($lock)
            $lock.artifacts[0].evidenceClass = 'unknown'
        }
    Assert-MutationRejected -Name 'extra-source' `
        -ExpectedMessage 'Conjunto divergente em artefatos' -Mutate {
            param($lock)
            $extra = [pscustomobject][ordered]@{
                projectId = 'h3-monitor'
                path = 'h3-monitor/output/validation/extra.csv'
                role = 'unexpected_extra_source'
                sha256 = '1' * 64
                evidenceClass = 'synthetic'
                verificationMethod = 'validated_snapshot'
            }
            $lock.artifacts = @($lock.artifacts) + $extra
        }
    Assert-MutationRejected -Name 'missing-source' `
        -ExpectedMessage 'Conjunto divergente em artefatos' -Mutate {
            param($lock)
            $lock.artifacts = @($lock.artifacts | Select-Object -SkipLast 1)
        }

    Write-Host 'Mutações do source lock rejeitadas com sucesso.' -ForegroundColor Green
    Write-Host "Casos negativos: $RejectedCount; baseline válido: 1."
}
finally {
    if (Test-Path -LiteralPath $ResolvedTempRoot) {
        Remove-Item -LiteralPath $ResolvedTempRoot -Recurse -Force
    }
}
