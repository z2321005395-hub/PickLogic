[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',
    [switch]$ExportArtifact
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'env.ps1') -Quiet

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$appRoot = Join-Path $repoRoot 'apps\mobile'
$flutter = Join-Path $env:PICKLOGIC_FLUTTER_ROOT 'bin\flutter.bat'
$mode = "--$($Configuration.ToLowerInvariant())"

Push-Location $appRoot
try {
    & $flutter build apk $mode
    if ($LASTEXITCODE -ne 0) {
        throw "Android $Configuration build failed."
    }
}
finally {
    Pop-Location
}

$sourceApk = Join-Path $appRoot "build\app\outputs\flutter-apk\app-$($Configuration.ToLowerInvariant()).apk"
if (-not (Test-Path -LiteralPath $sourceApk -PathType Leaf)) {
    throw 'Flutter reported success but the expected APK was not found.'
}

$artifact = $sourceApk
if ($ExportArtifact) {
    $artifactDirectory = Join-Path $repoRoot 'codex_output\artifacts'
    New-Item -ItemType Directory -Path $artifactDirectory -Force | Out-Null
    $artifact = Join-Path $artifactDirectory "picklogic-mobile-v0.1.0-alpha-$($Configuration.ToLowerInvariant()).apk"
    if (Test-Path -LiteralPath $artifact) {
        throw 'The export artifact already exists; preserve it or remove it explicitly before rebuilding.'
    }
    Copy-Item -LiteralPath $sourceApk -Destination $artifact
}

$file = Get-Item -LiteralPath $artifact
$hash = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash
$relative = [System.IO.Path]::GetRelativePath($repoRoot, $artifact)
Write-Output "ANDROID_BUILD_OK configuration=$Configuration artifact=$relative bytes=$($file.Length) sha256=$hash"
