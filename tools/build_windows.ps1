[CmdletBinding()]
param(
    [ValidateSet('Standard', 'Pro')]
    [string]$Edition = 'Standard',
    [switch]$ExportArtifact
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'env.ps1') -Quiet

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$appRoot = Join-Path $repoRoot 'apps\desktop'
$flutter = Join-Path $env:PICKLOGIC_FLUTTER_ROOT 'bin\flutter.bat'
$target = if ($Edition -eq 'Pro') { 'lib/main_pro.dart' } else { 'lib/main_standard.dart' }

Push-Location $appRoot
try {
    & $flutter build windows --release --target $target
    if ($LASTEXITCODE -ne 0) {
        throw "Windows $Edition build failed."
    }
}
finally {
    Pop-Location
}

$releaseDirectory = Join-Path $appRoot 'build\windows\x64\runner\Release'
if (-not (Test-Path -LiteralPath $releaseDirectory -PathType Container)) {
    throw 'Flutter reported success but the expected Windows release directory was not found.'
}

$totalBytes = (Get-ChildItem -LiteralPath $releaseDirectory -Recurse -File | Measure-Object -Property Length -Sum).Sum
$summary = "WINDOWS_BUILD_OK edition=$Edition installed_bytes=$totalBytes"

if ($ExportArtifact) {
    $artifactDirectory = Join-Path $repoRoot 'codex_output\artifacts'
    New-Item -ItemType Directory -Path $artifactDirectory -Force | Out-Null
    $slug = $Edition.ToLowerInvariant()
    $artifact = Join-Path $artifactDirectory "picklogic-windows-$slug-v0.1.0-alpha.zip"
    if (Test-Path -LiteralPath $artifact) {
        throw 'The export artifact already exists; preserve it or remove it explicitly before rebuilding.'
    }
    Compress-Archive -Path (Join-Path $releaseDirectory '*') -DestinationPath $artifact -CompressionLevel Optimal
    $file = Get-Item -LiteralPath $artifact
    $hash = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash
    $relative = [System.IO.Path]::GetRelativePath($repoRoot, $artifact)
    $summary += " artifact=$relative package_bytes=$($file.Length) sha256=$hash"
}

Write-Output $summary
