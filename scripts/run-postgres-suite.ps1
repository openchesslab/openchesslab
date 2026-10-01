param(
    [string]$DatabaseUrl = $env:DATABASE_URL,
    [switch]$SkipMigrations
)

$ErrorActionPreference = "Stop"

function Test-RepoRoot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    return (
        (Test-Path (Join-Path $Path "mix.exs")) -and
        (Test-Path (Join-Path $Path "apps\analysis\mix.exs")) -and
        (Test-Path (Join-Path $Path "apps\database\mix.exs"))
    )
}

function Find-RepoRoot {
    $starts = @(
        (Get-Location).Path,
        $PSScriptRoot
    ) | Select-Object -Unique

    foreach ($start in $starts) {
        if ([string]::IsNullOrWhiteSpace($start)) {
            continue
        }

        $current = (Resolve-Path $start).Path

        while ($true) {
            if (Test-RepoRoot $current) {
                return $current
            }

            $parent = Split-Path -Parent $current

            if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) {
                break
            }

            $current = $parent
        }
    }

    throw "Could not find the OpenChessLab repository root. Run this script from the repository or place it in the repository (for example under scripts/)."
}

if ([string]::IsNullOrWhiteSpace($DatabaseUrl)) {
    $DatabaseUrl = "ecto://openchesslab:openchesslab@localhost/openchesslab_test"
}

$repoRoot = Find-RepoRoot

$previousDatabaseUrl = $env:DATABASE_URL
$previousMixEnv = $env:MIX_ENV

try {
    $env:DATABASE_URL = $DatabaseUrl
    $env:MIX_ENV = "test"

    Write-Host "OpenChessLab PostgreSQL suite"
    Write-Host "Repository: $repoRoot"

    if (-not $SkipMigrations) {
        Write-Host ""
        Write-Host "==> Running PostgreSQL migrations"

        Push-Location (Join-Path $repoRoot "apps\database")
        try {
            & mix ecto.migrate

            if ($LASTEXITCODE -ne 0) {
                throw "PostgreSQL migration failed with exit code $LASTEXITCODE."
            }
        }
        finally {
            Pop-Location
        }
    }
    else {
        Write-Host ""
        Write-Host "==> Skipping PostgreSQL migrations"
    }

    Write-Host ""
    Write-Host "==> Running Analysis test suite against PostgreSQL"

    Push-Location (Join-Path $repoRoot "apps\analysis")
    try {
        & mix test

        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }

    Write-Host ""
    Write-Host "PostgreSQL suite passed."
}
finally {
    $env:DATABASE_URL = $previousDatabaseUrl
    $env:MIX_ENV = $previousMixEnv
}