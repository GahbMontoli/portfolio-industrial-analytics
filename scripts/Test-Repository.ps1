[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Errors = [System.Collections.Generic.List[string]]::new()

Get-ChildItem -LiteralPath $ProjectRoot -Recurse -Filter '*.ps1' -File |
    Where-Object { $_.FullName -notlike '*\data\curated\*' } |
    ForEach-Object {
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $_.FullName,
            [ref]$tokens,
            [ref]$parseErrors)
        foreach ($parseError in $parseErrors) {
            $Errors.Add("PowerShell inválido em $($_.FullName): $($parseError.Message)")
        }
    }

Get-ChildItem -LiteralPath $ProjectRoot -Recurse -Filter '*.json' -File |
    Where-Object { $_.FullName -notlike '*\data\curated\*' } |
    ForEach-Object {
        try {
            Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json | Out-Null
        }
        catch {
            $Errors.Add("JSON inválido em $($_.FullName): $($_.Exception.Message)")
        }
    }

Get-ChildItem -LiteralPath $ProjectRoot -Recurse -Filter '*.md' -File |
    ForEach-Object {
        $file = $_
        $content = Get-Content -LiteralPath $file.FullName -Raw
        [regex]::Matches($content, '\[[^\]]+\]\((?!https?://|#)([^)]+)\)') |
            ForEach-Object {
                $target = $_.Groups[1].Value.Split('#')[0]
                if ($target -and
                    -not (Test-Path -LiteralPath (Join-Path $file.DirectoryName $target))) {
                    $Errors.Add("Link local ausente em $($file.FullName): $target")
                }
            }
    }

if ($Errors.Count -gt 0) {
    throw ($Errors -join [Environment]::NewLine)
}

Write-Host 'Fontes do repositório validadas com sucesso.' -ForegroundColor Green
