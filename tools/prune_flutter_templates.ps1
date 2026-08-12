[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.git'))) {
    throw "Expected a Git repository root: $repoRoot"
}

$relativeTargets = @(
    'platform\windows_bridge\example',
    'platform\android_bridge\example',
    'apps\desktop\.dart_tool',
    'apps\mobile\.dart_tool',
    'platform\windows_bridge\.dart_tool',
    'platform\android_bridge\.dart_tool',
    'apps\desktop\pubspec.lock',
    'apps\mobile\pubspec.lock',
    'platform\windows_bridge\pubspec.lock',
    'platform\android_bridge\pubspec.lock'
)

$removed = [System.Collections.Generic.List[string]]::new()
foreach ($relative in $relativeTargets) {
    $target = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $relative))
    if (-not $target.StartsWith($repoRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing target outside repository: $target"
    }
    if ([System.IO.Directory]::Exists($target)) {
        [System.IO.Directory]::Delete($target, $true)
        $removed.Add($relative)
    } elseif ([System.IO.File]::Exists($target)) {
        [System.IO.File]::Delete($target)
        $removed.Add($relative)
    }
}

[pscustomobject]@{
    Repository = $repoRoot
    Removed = @($removed)
} | ConvertTo-Json -Depth 3
