# Recipe-to-example parity: what the checkpoints generate must match the completed example.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/../..").Path
$tokens = @{ PREFIX = 'almlab'; PASCAL = 'Almlab' }
$failures = [System.Collections.Generic.List[string]]::new()

function Get-Normalized([string]$Text) { ($Text -replace "`r`n", "`n").Trim() }
function Expand-ForCompare([string]$Template) {
    $content = Get-Content -Raw -LiteralPath "$root/.lab-scripts/templates/$Template"
    foreach ($key in $tokens.Keys) { $content = $content.Replace("__${key}__", $tokens[$key]) }
    Get-Normalized $content
}
function Test-Same([string]$Template, [string]$Target) {
    $path = "$root/$Target"
    if (-not (Test-Path $path)) { $failures.Add("$Target is missing (generated from $Template)."); return }
    if ((Expand-ForCompare $Template) -ne (Get-Normalized (Get-Content -Raw $path))) {
        $failures.Add("$Target has drifted from template $Template.")
    }
}

# CP11 patches these after generation: everything the template wrote must still be there.
function Test-Extends([string]$Template, [string]$Target) {
    $path = "$root/$Target"
    if (-not (Test-Path $path)) { $failures.Add("$Target is missing (generated from $Template)."); return }
    $actual = (Get-Normalized (Get-Content -Raw $path)) -split "`n"
    $cursor = 0
    foreach ($line in ((Expand-ForCompare $Template) -split "`n" | Where-Object { $_.Trim() })) {
        $found = $false
        for (; $cursor -lt $actual.Count; $cursor++) { if ($actual[$cursor] -eq $line) { $found = $true; $cursor++; break } }
        if (-not $found) { $failures.Add("$Target no longer contains template line from ${Template}: $($line.Trim())"); return }
    }
}

# Templates expanded verbatim by the scaffolds.
foreach ($name in 'SubtractQuantityPlugin', 'ValidateWarehouseTransactionPlugin', 'WarehouseStock') {
    Test-Same "07-plugins/$name.cs" "src/Plugins.Warehouse/$name.cs"
}
foreach ($name in 'SubtractQuantityPluginTests', 'ValidateWarehouseTransactionPluginTests') {
    Test-Same "14-tests-unit/$name.cs" "src/Tests.Plugins/$name.cs"
}
foreach ($pair in @(
    @('optionSets.ts', 'utils/optionSets.ts'), @('operationResult.ts', 'utils/operationResult.ts'),
    @('router.tsx', 'router.tsx'), @('_layout.tsx', 'pages/_layout.tsx'),
    @('warehouse-items.tsx', 'pages/warehouse-items.tsx'), @('warehouse-item-detail.tsx', 'pages/warehouse-item-detail.tsx'),
    @('transactions.tsx', 'pages/transactions.tsx'), @('locations.tsx', 'pages/locations.tsx'))) {
    if ($pair[0] -eq 'warehouse-item-detail.tsx') { Test-Extends "05f-code-app/$($pair[0])" "src/Apps.WarehousePicking/src/$($pair[1])"; continue }
    Test-Same "05f-code-app/$($pair[0])" "src/Apps.WarehousePicking/src/$($pair[1])"
}
foreach ($file in Get-ChildItem "$root/.lab-scripts/workflows" -Filter '*.yml') {
    $installed = "$root/.github/workflows/$($file.Name)"
    if (-not (Test-Path $installed)) { $failures.Add("Installed workflow $($file.Name) is missing."); continue }
    if ((Get-Normalized (Get-Content -Raw $file.FullName)) -ne (Get-Normalized (Get-Content -Raw $installed))) {
        $failures.Add("Installed workflow $($file.Name) differs from its recipe copy.")
    }
}

# Plugin step registrations: each message the plugins claim to handle is registered.
$steps = @{}
foreach ($file in Get-ChildItem "$root/src/Solutions.Logic/SdkMessageProcessingSteps/*.xml") {
    [xml]$xml = Get-Content -Raw $file.FullName
    $step = $xml.SdkMessageProcessingStep
    $steps[$step.Name] = $xml
}
foreach ($expected in @(
    'Plugins.Warehouse.SubtractQuantityPlugin: Create of almlab_warehousetransaction',
    'Plugins.Warehouse.SubtractQuantityPlugin: Update of almlab_warehousetransaction',
    'Plugins.Warehouse.SubtractQuantityPlugin: Delete of almlab_warehousetransaction',
    'Plugins.Warehouse.ValidateWarehouseTransactionPlugin: Create of almlab_warehousetransaction',
    'Plugins.Warehouse.ValidateWarehouseTransactionPlugin: Create of almlab_warehouseitem',
    'Plugins.Warehouse.ValidateWarehouseTransactionPlugin: Update of almlab_warehouseitem')) {
    if (-not $steps.ContainsKey($expected)) { $failures.Add("Missing plugin step: $expected"); continue }
    if ($expected -match 'SubtractQuantityPlugin: (Update|Delete)') {
        $image = $steps[$expected].SelectSingleNode('//SdkMessageProcessingStepImage')
        if (-not $image -or $image.EntityAlias -ne 'Before' -or $image.Attributes -notlike '*almlab_quantity*') {
            $failures.Add("Step lacks the Before image: $expected")
        }
    }
}
[xml]$solution = Get-Content -Raw "$root/src/Solutions.Logic/Other/Solution.xml"
foreach ($id in $steps.Values | ForEach-Object { $_.SdkMessageProcessingStep.SdkMessageProcessingStepId }) {
    if (-not $solution.SelectSingleNode("//RootComponent[@type='92' and translate(@id,'ABCDEF','abcdef')='$($id.ToLowerInvariant())']")) {
        $failures.Add("Step $id is not a root component of Solutions.Logic.")
    }
}
$assemblyRoots = @($solution.SelectNodes("//RootComponent[@type='91']"))
if ($assemblyRoots.Count -ne 1) { $failures.Add("Expected one plugin assembly root; found $($assemblyRoots.Count).") }

# Navigation and app components: Product reachable in the model-driven app.
$sitemap = Get-Content -Raw "$root/src/Solutions.UI/AppModuleSiteMaps/almlab_warehouseapp/AppModuleSiteMap.xml"
if ($sitemap -notmatch 'almlab_product') { $failures.Add('The sitemap does not navigate to Product.') }
$appModule = Get-Content -Raw "$root/src/Solutions.UI/AppModules/almlab_warehouseapp/AppModule.xml"
if ($appModule -notmatch 'almlab_product') { $failures.Add('The app module does not include Product.') }
if ($sitemap -match 'dashboard' -and -not (Test-Path "$root/src/GenPages.Dashboard")) {
    $failures.Add('Navigation points at a dashboard that is not in the repository.')
}

# Roles: both personas can reach what the walkthrough uses.
foreach ($role in 'Warehouse manager', 'Warehouse worker') {
    $roleText = Get-Content -Raw "$root/src/Solutions.Security/Roles/$role.xml"
    foreach ($entity in 'almlab_product', 'almlab_warehouseitem', 'almlab_warehousetransaction') {
        if ($roleText -notmatch [regex]::Escape($entity)) { $failures.Add("$role has no privileges for $entity.") }
    }
}

# No placeholder or personal leftovers in the example's sources.
foreach ($file in Get-ChildItem "$root/src" -Recurse -File -Include *.xml, *.cs, *.ts, *.tsx, *.json, *.csproj |
        Where-Object { $_.FullName -notmatch '[\\/](obj|bin|node_modules|Workflows)[\\/]' }) {
    if ((Get-Content -Raw -LiteralPath $file.FullName) -match '__[A-Z_]+__|__publisher-prefix__') {
        $failures.Add("Unreplaced template token in $($file.FullName.Substring($root.Length + 1)).")
    }
}

if ($failures.Count) { throw "Recipe/example parity failed:`n - " + ($failures -join "`n - ") }
Write-Host 'Recipe output and completed example are in parity.'
