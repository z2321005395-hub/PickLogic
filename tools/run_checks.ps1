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

    Invoke-Checked -Label 'Quick module tests' -Action { & $dart run tools/run_module_tests.dart quick }

    if ($Scope -eq 'Full') {
        Invoke-Checked -Label 'Remaining module tests' -Action { & $dart run tools/run_module_tests.dart remaining }
    }

    Invoke-Checked -Label 'Dependency license check' -Action { & $dart run tools/dependency_license_check.dart }
    & (Join-Path $PSScriptRoot 'privacy_check.ps1')
    Write-Output "PICKLOGIC_CHECKS_OK scope=$Scope"
}
finally {
    Pop-Location
}
