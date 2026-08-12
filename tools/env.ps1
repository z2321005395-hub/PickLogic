[CmdletBinding()]
param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Resolve-RequiredDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label was not found. Set the corresponding PICKLOGIC_* environment override."
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

$defaultFlutterRoot = Join-Path $env:USERPROFILE 'develop\picklogic-toolchain\flutter'
$defaultAndroidToolchainRoot = Join-Path $env:USERPROFILE 'Desktop\ttdt\toolchains'

$flutterRootCandidate = $env:PICKLOGIC_FLUTTER_ROOT
if ([string]::IsNullOrWhiteSpace($flutterRootCandidate)) {
    $flutterRootCandidate = $defaultFlutterRoot
}

$androidToolchainCandidate = $env:PICKLOGIC_ANDROID_TOOLCHAIN_ROOT
if ([string]::IsNullOrWhiteSpace($androidToolchainCandidate)) {
    $androidToolchainCandidate = $defaultAndroidToolchainRoot
}

$flutterRoot = Resolve-RequiredDirectory -Path $flutterRootCandidate -Label 'Flutter SDK'
$androidToolchainRoot = Resolve-RequiredDirectory -Path $androidToolchainCandidate -Label 'TTDT Android toolchain'
$androidSdkRoot = Resolve-RequiredDirectory -Path (Join-Path $androidToolchainRoot 'android-sdk') -Label 'Android SDK'

$jdkRoot = Get-ChildItem -LiteralPath (Join-Path $androidToolchainRoot 'jdk17') -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bin\java.exe') } |
    Sort-Object Name -Descending |
    Select-Object -First 1 -ExpandProperty FullName
if ([string]::IsNullOrWhiteSpace($jdkRoot)) {
    throw 'A Java 17 runtime was not found in the TTDT toolchain.'
}

$gradleRoot = Get-ChildItem -LiteralPath (Join-Path $androidToolchainRoot 'gradle') -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bin\gradle.bat') } |
    Sort-Object Name -Descending |
    Select-Object -First 1 -ExpandProperty FullName
if ([string]::IsNullOrWhiteSpace($gradleRoot)) {
    throw 'Gradle was not found in the TTDT toolchain.'
}

$env:JAVA_HOME = $jdkRoot
$env:ANDROID_HOME = $androidSdkRoot
$env:ANDROID_SDK_ROOT = $androidSdkRoot
$env:PICKLOGIC_FLUTTER_ROOT = $flutterRoot
$env:PICKLOGIC_ANDROID_TOOLCHAIN_ROOT = $androidToolchainRoot

$requiredPathEntries = @(
    (Join-Path $flutterRoot 'bin'),
    (Join-Path $jdkRoot 'bin'),
    (Join-Path $androidSdkRoot 'platform-tools'),
    (Join-Path $androidSdkRoot 'cmdline-tools\latest\bin'),
    (Join-Path $androidSdkRoot 'emulator'),
    (Join-Path $gradleRoot 'bin')
)

$pathEntries = @($env:Path -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
foreach ($entry in [System.Linq.Enumerable]::Reverse([string[]]$requiredPathEntries)) {
    $pathEntries = @($pathEntries | Where-Object { -not [string]::Equals($_.TrimEnd('\'), $entry.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase) })
    $pathEntries = @($entry) + $pathEntries
}
$env:Path = $pathEntries -join ';'

if (-not $Quiet) {
    Write-Output 'PICKLOGIC_ENV_READY flutter=true android_sdk=true java17=true gradle=true ttdt_preferred=true'
}
