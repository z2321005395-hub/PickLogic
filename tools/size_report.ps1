[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$artifactRoot = Join-Path $repoRoot 'codex_output\artifacts'

if (-not (Test-Path -LiteralPath $artifactRoot -PathType Container)) {
    Write-Output 'SIZE_REPORT_EMPTY artifacts=0'
    exit 0
}

$budgets = @{
    'picklogic-mobile' = 40MB
    'picklogic-windows-standard' = 80MB
    'picklogic-windows-pro' = 130MB
}

$artifacts = @(Get-ChildItem -LiteralPath $artifactRoot -File | Sort-Object Name)
if ($artifacts.Count -eq 0) {
    Write-Output 'SIZE_REPORT_EMPTY artifacts=0'
    exit 0
}

$overBudget = $false
foreach ($artifact in $artifacts) {
    $budgetKey = $budgets.Keys | Where-Object { $artifact.Name.StartsWith($_, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if ($null -eq $budgetKey) {
        Write-Output "SIZE_REPORT artifact=$($artifact.Name) bytes=$($artifact.Length) budget=unassigned"
        continue
    }

    $budget = $budgets[$budgetKey]
    $status = if ($artifact.Length -le $budget) { 'within' } else { 'over' }
    if ($status -eq 'over') {
        $overBudget = $true
    }
    Write-Output "SIZE_REPORT artifact=$($artifact.Name) bytes=$($artifact.Length) budget_bytes=$budget status=$status"
}

if ($overBudget) {
    throw 'At least one base artifact exceeds its declared package-size budget.'
}
