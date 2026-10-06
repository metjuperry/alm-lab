#!/usr/bin/env pwsh
#
# ╔════════════════════════════════════════════════════════════════════════════════════════╗
# ║                       CP15: Implement unit tests                                       ║
# ╚════════════════════════════════════════════════════════════════════════════════════════╝
#
# The fast layers of the test pyramid. CP14 gave us browser UI tests - thorough but slow
# and environment-bound. This checkpoint adds the two layers underneath, both running in
# milliseconds with no Dataverse environment at all:
#   - Tests.Plugins   - FakeXrmEasy fakes the whole Dataverse pipeline in memory, so the
#                       plugin logic (stock validation, inbound/outbound math) is tested
#                       as plain C#.
#   - Tests.Scripts   - Jest loads the built web-resource bundle with a mocked Xrm object,
#                       so form scripts and ribbon actions are tested as plain JavaScript.
#
# The tests are adapted to OUR app: the plugins require a transaction type and treat
# Inbound (add stock) and Outbound (validate + subtract) differently - tests document that.
#
# One honest constraint: the plugin assembly itself must stay net472 - the Dataverse
# sandbox still runs .NET Framework. The tests don't share that constraint: the template
# targets modern .NET with FakeXrmEasy 3.x, so the whole suite runs anywhere (Codespaces,
# the ubuntu CI runner). The scaffold only bridges the net10-to-net472 project reference -
# see 14-tests-unit.ps1.
#
# Run:  .lab-scripts/CP15-implement-unit-tests.ps1
# ──────────────────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/lib/Lab.Common.ps1"
$PublisherName   = Get-LabValue 'publisherName'   'ALMLab'
$PublisherPrefix = Get-LabValue 'publisherPrefix' 'almlab'

Write-Step "CP15 — Unit tests (plugins + scripts)"
Push-Location $LabRoot
try {
    . "$PSScriptRoot/scaffold/14-tests-unit.ps1"

    Write-Info "Building the current Scripts.UI bundle before testing it..."
    Invoke-LabNative dotnet build src/Scripts.UI/Scripts.UI.csproj --nologo --verbosity quiet
    if (-not (Test-Path 'src/Tests.Scripts/node_modules/.bin/jest')) {
        if (Test-Path 'src/Tests.Scripts/package-lock.json') {
            Invoke-LabNative npm ci --prefix src/Tests.Scripts
        } else {
            Invoke-LabNative npm install --prefix src/Tests.Scripts
        }
    }
    Write-Info "Running script unit tests (Jest)..."
    Invoke-LabNative npm test --prefix src/Tests.Scripts -- --ci
    if ($LASTEXITCODE -ne 0) { Write-Err "Script tests failed"; exit 1 }
    Write-Ok "Script unit tests passed"

    # ── Run plugin tests (FakeXrmEasy) ──
    Invoke-LabNative dotnet test src/Tests.Plugins/Tests.Plugins.csproj --nologo
    if ($LASTEXITCODE -ne 0) { Write-Err "Plugin tests failed"; exit 1 }
    Write-Ok "Plugin unit tests passed"
    Invoke-LabNative dotnet publish src/Packages.Main/Packages.Main.csproj -c Release --nologo --verbosity quiet
    & "$PSScriptRoot/Test-LabArtifact.ps1" -Package 'src/Packages.Main/bin/Release/Packages.Main.pdpkg.zip' -Complete

    # ── Install the unit-tests workflow so both suites run on every PR ──
    $wf = Join-Path $LabRoot ".github/workflows"
    New-Item -ItemType Directory -Path $wf -Force | Out-Null
    Copy-Item "$PSScriptRoot/workflows/unit-tests.yml" $wf -Force
    if ($env:LAB_LOCAL_MODE -ne '1') {
        $repo = Get-LabRepository
        $rulesetId = Get-LabValue 'mainRulesetId'
        $ruleset = Invoke-LabNative gh api "repos/$repo/rulesets/$rulesetId" | ConvertFrom-Json -AsHashtable
        $required = $ruleset.rules | Where-Object type -eq 'required_status_checks'
        if (-not $required) { throw 'Run CP13 before making unit tests required.' }
        if ('unit-tests' -notin $required.parameters.required_status_checks.context) {
            $required.parameters.required_status_checks += @{ context = 'unit-tests' }
            $temp = New-TemporaryFile
            try {
                @{ rules = $ruleset.rules } | ConvertTo-Json -Depth 20 | Set-Content $temp.FullName
                Invoke-LabNative gh api -X PUT "repos/$repo/rulesets/$rulesetId" --input $temp.FullName | Out-Null
            } finally { Remove-Item $temp.FullName }
        }
    }
    Write-Ok "Installed unit-tests.yml; live runs require its check before merge"
} finally { Pop-Location }

Save-Checkpoint -Id "cp15" -Message "Add plugin and script unit test projects with CI workflow" -Body @'
Add the fast layers of the test pyramid so warehouse logic is verified without a Dataverse environment. Plugin logic is covered with FakeXrmEasy and the form/ribbon scripts with Jest against the built web-resource bundle.

## Changes
- add src/Tests.Plugins with FakeXrmEasy tests for both warehouse plugins
- add src/Tests.Scripts with Jest tests for form, ribbon, and grid bridge scripts
- add .github/workflows/unit-tests.yml running both suites on every PR
## Testing
- plugin tests pass via dotnet test; script tests pass via npm test
'@
Write-Host "`nCore source checkpoints complete. Verify Dev/Test deployment and the live app before declaring the lab complete." -ForegroundColor Cyan
Write-Host "Optional: .lab-scripts/CP16-plan-tests-with-agent.ps1" -ForegroundColor Cyan
