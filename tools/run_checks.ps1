[CmdletBinding()]
param(
    [ValidateSet('Quick', 'Full')]
    [string]$Scope = 'Quick'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'env.ps1') -Quiet

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$dart = Join-Path $env:PICKLOGIC_FLUTTER_ROOT 'bin\dart.bat'
$flutter = Join-Path $env:PICKLOGIC_FLUTTER_ROOT 'bin\flutter.bat'

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE."
    }
}

Push-Location $repoRoot
try {
    Invoke-Checked -Label 'Dart format check' -Action { & $dart format --output=none --set-exit-if-changed . }
    Invoke-Checked -Label 'Dart analysis' -Action { & $dart analyze }

    $quickPackages = @(
        'packages/core_models',
        'packages/classification_rules',
        'packages/search_index',
        'packages/duplicate_engine',
        'packages/insight_engine',
        'packages/operation_planner',
        'packages/preview_core',
        'packages/literature_core',
        'packages/research_core',
        'packages/system_insight_core',
        'test_fixtures'
    )
    foreach ($package in $quickPackages) {
        Push-Location (Join-Path $repoRoot $package)
        try {
            Invoke-Checked -Label "$package tests" -Action { & $dart test --reporter compact }
        }
        finally {
            Pop-Location
        }
    }

    if ($Scope -eq 'Full') {
        Push-Location (Join-Path $repoRoot 'packages/file_index')
        try {
            Invoke-Checked -Label 'file_index tests' -Action { & $dart test --reporter compact }
        }
        finally {
            Pop-Location
        }

        foreach ($flutterPackage in @('packages/shared_ui', 'platform/windows_bridge', 'platform/android_bridge', 'apps/desktop', 'apps/mobile')) {
            Push-Location (Join-Path $repoRoot $flutterPackage)
            try {
                Invoke-Checked -Label "$flutterPackage tests" -Action { & $flutter test --no-pub --reporter compact }
            }
            finally {
                Pop-Location
            }
        }
    }

    Invoke-Checked -Label 'Dependency license check' -Action { & $dart run tools/dependency_license_check.dart }
    & (Join-Path $PSScriptRoot 'privacy_check.ps1')
    Write-Output "PICKLOGIC_CHECKS_OK scope=$Scope"
}
finally {
    Pop-Location
}
