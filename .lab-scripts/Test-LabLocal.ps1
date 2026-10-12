#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [string]$Baseline = 'ca8221504a9628375a690b275633dad1c8ec5a07',
    [ValidateRange(1, 15)][int]$Through = 15,
    [string]$Destination
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/..").Path
if (-not $Destination) { $Destination = Join-Path ([IO.Path]::GetTempPath()) "alm-lab-rehearsal-$([guid]::NewGuid().ToString('N'))" }
if (Test-Path $Destination) { throw "Destination must not exist: $Destination" }
New-Item -ItemType Directory $Destination | Out-Null
$archive = Join-Path $Destination 'starter.tar'
git -C $root archive $Baseline -o $archive
if ($LASTEXITCODE -ne 0) { throw "Baseline $Baseline is unavailable; fetch upstream first." }
tar -xf $archive -C $Destination
if ($LASTEXITCODE -ne 0) { throw 'Could not extract starter.' }
Remove-Item $archive
# Overlay only the authored recipes, never generated src/, state, tags, or caches.
Copy-Item "$PSScriptRoot/*" (Join-Path $Destination '.lab-scripts') -Recurse -Force
$oldEnvironment = @{}
foreach ($key in @('LAB_LOCAL_MODE', 'LAB_DISPOSABLE', 'LAB_AUTO', 'LAB_AUTO_MERGE')) {
    $oldEnvironment[$key] = [Environment]::GetEnvironmentVariable($key)
}
Push-Location $Destination
try {
    git init -b main --quiet
    git config user.email 'rehearsal@local.invalid'
    git config user.name 'Lab rehearsal'
    git add --all
    git commit -m 'Clean upstream starter with candidate recipes' -m 'Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>' --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Could not initialize rehearsal repository.' }
    $env:LAB_LOCAL_MODE = '1'
    $env:LAB_DISPOSABLE = '1'
    $env:LAB_AUTO = '1'
    $env:LAB_AUTO_MERGE = '1'
    foreach ($number in 1..$Through) {
        $files = @(Get-ChildItem ".lab-scripts/CP$('{0:d2}' -f $number)-*.ps1")
        if ($files.Count -ne 1) { throw "Expected exactly one core checkpoint $number." }
        Write-Host "Rehearsing $($files[0].Name) in $Destination"
        & pwsh -NoProfile -NonInteractive -File $files[0].FullName
        if ($LASTEXITCODE -ne 0) { throw "Checkpoint $number failed. Retained isolated checkout: $Destination" }
    }
    Write-Host "Local source rehearsal finished: $Destination. No live deployment was performed."
} finally {
    Pop-Location
    foreach ($key in $oldEnvironment.Keys) { [Environment]::SetEnvironmentVariable($key, $oldEnvironment[$key]) }
}
