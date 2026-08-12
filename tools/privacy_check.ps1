[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

if (-not (Get-Command rg -ErrorAction SilentlyContinue)) {
    throw 'ripgrep (rg) is required for the privacy check.'
}

$patterns = @(
    ('C:' + '\\Users\\[^\\\r\n\t ]+'),
    ('C:' + '/Users/[^/\r\n\t ]+'),
    '\bgithub_pat_[A-Za-z0-9_]{20,}\b',
    '\bgh[pousr]_[A-Za-z0-9]{20,}\b',
    '\bAIza[0-9A-Za-z_-]{30,}\b',
    '\bsk-[A-Za-z0-9_-]{20,}\b',
    '(?i)-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    '(?i)\badb(?:\.exe)?\s+-s\s+[A-Za-z0-9._:-]{6,}',
    '(?i)(?:api[_-]?key|access[_-]?token|client[_-]?secret)\s*[:=]\s*["''][A-Za-z0-9_./+=:-]{12,}["'']'
)

$arguments = @(
    '--files-with-matches',
    '--hidden',
    '--pcre2',
    '--glob', '!.git/**',
    '--glob', '!.dart_tool/**',
    '--glob', '!build/**',
    '--glob', '!**/build/**',
    '--glob', '!codex_output/**',
    '--glob', '!output_test/**'
)
foreach ($pattern in $patterns) {
    $arguments += @('--regexp', $pattern)
}
$arguments += '.'

Push-Location $repoRoot
try {
    $matches = @(& rg @arguments 2>$null)
    $rgExitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

if ($rgExitCode -gt 1) {
    throw "Privacy scan failed to run (rg exit code $rgExitCode)."
}

if ($matches.Count -gt 0) {
    Write-Output 'PRIVACY_CHECK_FAILED files:'
    $matches | Sort-Object -Unique | ForEach-Object { Write-Output "- $_" }
    throw 'Potential private path, credential, key, token, or device identifier found. Matching contents were intentionally not printed.'
}

Write-Output 'PRIVACY_CHECK_OK findings=0'
