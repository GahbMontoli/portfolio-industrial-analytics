[CmdletBinding()]
param(
    [string]$LockPath,
    [string]$H3Root,
    [string]$SimulatorRoot,
    [string]$CmmsRoot,
    [string]$OutputPath,
    [AllowEmptyCollection()]
    [string[]]$ExpectedArtifactPaths = @(),
    [switch]$PassThru
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
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $ProjectRoot 'data\curated\source-lock-validation.json'
}

$AllowedEvidenceClasses = @(
    'synthetic', 'official_raw', 'lab_observed', 'field_observed', 'derived'
)
$AllowedVerificationMethods = @(
    'git_blob_at_commit',
    'reproduced_from_commit',
    'manifest_hash_chain',
    'validated_snapshot',
    'validated_export_snapshot'
)
$RepositoryRoots = [ordered]@{
    'h3-monitor' = [System.IO.Path]::GetFullPath($H3Root)
    'industrial-simulator-3d' = [System.IO.Path]::GetFullPath($SimulatorRoot)
    'copiloto-confiabilidade' = [System.IO.Path]::GetFullPath($CmmsRoot)
}

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

function Assert-UniqueValues {
    param(
        [Parameter(Mandatory)]
        [object[]]$Values,
        [Parameter(Mandatory)]
        [string]$Context
    )

    if (@($Values | Sort-Object -Unique).Count -ne $Values.Count) {
        throw "Valores duplicados em ${Context}."
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

    $actualSet = @($Actual | Sort-Object -Unique)
    $expectedSet = @($Expected | Sort-Object -Unique)
    $actualFingerprint = @($actualSet | ForEach-Object { [string]$_ }) -join "`n"
    $expectedFingerprint = @($expectedSet | ForEach-Object { [string]$_ }) -join "`n"
    if ($actualSet.Count -ne $expectedSet.Count -or
        $actualFingerprint -cne $expectedFingerprint) {
        throw "Conjunto divergente em ${Context}: esperado=[$($expectedSet -join ', ')]; atual=[$($actualSet -join ', ')]"
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory)]
        [string]$Root,
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $output = @(& git -C $Root @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Git falhou em $Root ($($Arguments -join ' ')): $($output -join ' ')"
    }
    return ($output -join "`n").Trim()
}

function Resolve-SafeArtifactPath {
    param(
        [Parameter(Mandatory)]
        [string]$PortablePath,
        [Parameter(Mandatory)]
        [string]$RepositoryDirectory
    )

    Assert-PortablePath -Path $PortablePath -Context 'source-lock.artifacts.path'
    Assert-Condition ($PortablePath.StartsWith(
        "$RepositoryDirectory/",
        [StringComparison]::Ordinal)) `
        "Artefato fora do diretório declarado do repositório: $PortablePath"

    $resolved = [System.IO.Path]::GetFullPath(
        (Join-Path $WorkspaceRoot $PortablePath.Replace('/', '\')))
    $repositoryRoot = [System.IO.Path]::GetFullPath(
        (Join-Path $WorkspaceRoot $RepositoryDirectory)).TrimEnd('\')
    Assert-Condition ($resolved.StartsWith(
        "$repositoryRoot\",
        [StringComparison]::OrdinalIgnoreCase)) `
        "Artefato escapou da raiz do repositório: $PortablePath"

    $cursor = $WorkspaceRoot
    foreach ($segment in $PortablePath.Split('/')) {
        $cursor = Join-Path $cursor $segment
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Reparse point não permitido na fonte travada: $PortablePath"
            }
        }
    }
    return $resolved
}

if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf)) {
    throw "Source lock ausente: $LockPath"
}
$Lock = Get-Content -LiteralPath $LockPath -Raw | ConvertFrom-Json
if ($Lock.schemaVersion -ne 1 -or $Lock.kind -ne 'portfolio-source-lock') {
    throw 'Source lock incompatível.'
}

$Repositories = @($Lock.repositories)
$Artifacts = @($Lock.artifacts)
Assert-Condition ($Repositories.Count -eq $RepositoryRoots.Count) `
    "O source lock deve declarar exatamente $($RepositoryRoots.Count) repositórios."
Assert-Condition ($Artifacts.Count -gt 0) 'O source lock não contém artefatos.'
Assert-UniqueValues @($Repositories.projectId) 'source-lock.repositories.projectId'
Assert-UniqueValues @($Repositories.workspaceDirectory) 'source-lock.repositories.workspaceDirectory'
Assert-UniqueValues @($Artifacts.path) 'source-lock.artifacts.path'
Assert-UniqueValues @($Artifacts.role) 'source-lock.artifacts.role'
Assert-SameSet @($Repositories.projectId) @($RepositoryRoots.Keys) `
    'repositórios do source lock'
if ($ExpectedArtifactPaths.Count -gt 0) {
    Assert-SameSet @($Artifacts.path) $ExpectedArtifactPaths `
        'artefatos do source lock versus fontes do gerador'
}

$RepositoryByProject = @{}
$RepositoryValidation = [System.Collections.Generic.List[object]]::new()
foreach ($repository in $Repositories) {
    $projectId = [string]$repository.projectId
    $root = $RepositoryRoots[$projectId]
    Assert-Condition ($repository.workspaceDirectory -match '^[a-z0-9][a-z0-9-]*$') `
        "Diretório de workspace inválido para $projectId."
    $expectedRoot = [System.IO.Path]::GetFullPath(
        (Join-Path $WorkspaceRoot $repository.workspaceDirectory))
    Assert-Condition ([string]::Equals(
        $root.TrimEnd('\'),
        $expectedRoot.TrimEnd('\'),
        [StringComparison]::OrdinalIgnoreCase)) `
        "Raiz divergente para $projectId."
    Assert-Condition (Test-Path -LiteralPath (Join-Path $root '.git')) `
        "Repositório Git ausente para ${projectId}: $root"
    Assert-Condition ($repository.repositoryUrl -match
        '^https://github\.com/GahbMontoli/[A-Za-z0-9._-]+\.git$') `
        "URL pública inválida para $projectId."
    Assert-Condition ($repository.publicRef -eq 'origin/main') `
        "Ref pública não suportada para $projectId."
    Assert-Condition ($repository.commitSha -cmatch '^[0-9a-f]{40}$') `
        "Commit SHA inválido para $projectId."
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($repository.verificationLimit)) `
        "Limite de verificação ausente para $projectId."

    $origin = Invoke-Git -Root $root -Arguments @('remote', 'get-url', 'origin')
    Assert-Condition ([string]::Equals(
        $origin,
        [string]$repository.repositoryUrl,
        [StringComparison]::OrdinalIgnoreCase)) `
        "Origin divergente para $projectId."
    $commitType = Invoke-Git -Root $root -Arguments @('cat-file', '-t', $repository.commitSha)
    Assert-Condition ($commitType -eq 'commit') `
        "Objeto travado não é commit em $projectId."
    & git -C $root merge-base --is-ancestor $repository.commitSha $repository.publicRef
    if ($LASTEXITCODE -ne 0) {
        throw "Commit travado não pertence a $($repository.publicRef) em $projectId."
    }

    $statusLines = @(& git -C $root status --porcelain)
    if ($LASTEXITCODE -ne 0) {
        throw "Não foi possível ler o estado Git de $projectId."
    }
    $headSha = Invoke-Git -Root $root -Arguments @('rev-parse', 'HEAD')
    $originMainSha = Invoke-Git -Root $root -Arguments @('rev-parse', $repository.publicRef)
    $RepositoryByProject[$projectId] = $repository
    $RepositoryValidation.Add([pscustomobject][ordered]@{
        project_id = $projectId
        repository_url = $repository.repositoryUrl
        locked_commit_sha = $repository.commitSha
        public_ref = $repository.publicRef
        public_ref_sha = $originMainSha
        head_sha = $headSha
        locked_commit_is_head = $headSha -eq $repository.commitSha
        working_tree_dirty = $statusLines.Count -gt 0
        working_tree_change_count = $statusLines.Count
        status = 'valid'
        verification_limit = $repository.verificationLimit
    }) | Out-Null
}

$ArtifactValidation = [System.Collections.Generic.List[object]]::new()
foreach ($artifact in $Artifacts) {
    $projectId = [string]$artifact.projectId
    Assert-Condition ($RepositoryByProject.ContainsKey($projectId)) `
        "Artefato referencia projeto inexistente: $projectId"
    Assert-Condition ($artifact.sha256 -cmatch '^[0-9a-f]{64}$') `
        "SHA-256 inválido no source lock para $($artifact.path)."
    Assert-Condition ($AllowedEvidenceClasses -contains $artifact.evidenceClass) `
        "Classe de evidência inválida para $($artifact.path)."
    Assert-Condition ($AllowedVerificationMethods -contains $artifact.verificationMethod) `
        "Método de verificação inválido para $($artifact.path)."
    Assert-Condition ($artifact.role -match '^[a-z][a-z0-9_]*$') `
        "Papel inválido para $($artifact.path)."

    $repository = $RepositoryByProject[$projectId]
    $resolvedPath = Resolve-SafeArtifactPath `
        -PortablePath $artifact.path `
        -RepositoryDirectory $repository.workspaceDirectory
    Assert-Condition (Test-Path -LiteralPath $resolvedPath -PathType Leaf) `
        "Artefato travado ausente: $($artifact.path)"
    $actualHash = (Get-FileHash -LiteralPath $resolvedPath -Algorithm SHA256).
        Hash.ToLowerInvariant()
    Assert-Condition ($actualHash -ceq $artifact.sha256) `
        "Hash divergente para o artefato travado: $($artifact.path)"

    $ArtifactValidation.Add([pscustomobject][ordered]@{
        project_id = $projectId
        path = $artifact.path
        role = $artifact.role
        sha256 = $actualHash
        bytes = (Get-Item -LiteralPath $resolvedPath).Length
        evidence_class = $artifact.evidenceClass
        verification_method = $artifact.verificationMethod
        status = 'valid'
    }) | Out-Null
}

$LockHash = (Get-FileHash -LiteralPath $LockPath -Algorithm SHA256).Hash.ToLowerInvariant()
$Report = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
    validationScope = 'local_source_lock'
    status = 'valid'
    lock = [ordered]@{
        path = [System.IO.Path]::GetRelativePath($ProjectRoot, $LockPath).Replace('\', '/')
        sha256 = $LockHash
    }
    summary = [ordered]@{
        repositories = $RepositoryValidation.Count
        artifacts = $ArtifactValidation.Count
        dirtyRepositories = @($RepositoryValidation | Where-Object working_tree_dirty).Count
    }
    limitations = @(
        'O lock identifica bytes e commits públicos; não é prova criptográfica de qual binário executou cada exportação.',
        'Refs origin/* são as referências remotas locais disponíveis; o validador não executa fetch.',
        'Artefatos ignorados continuam fora do Git upstream e devem ser regenerados ou preservados separadamente.'
    )
    repositories = @($RepositoryValidation)
    artifacts = @($ArtifactValidation)
}

$OutputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$Report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8

Write-Host 'Source lock do portfólio validado com sucesso.' -ForegroundColor Green
Write-Host ("Repositórios: {0}; artefatos: {1}; árvores sujas: {2}; relatório: {3}" -f `
    $RepositoryValidation.Count,
    $ArtifactValidation.Count,
    $Report.summary.dirtyRepositories,
    $OutputPath)
if ($PassThru) {
    [pscustomobject]$Report
}
