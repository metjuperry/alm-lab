#
# ╔════════════════════════════════════════════════════════════════════════════════════════╗
# ║          08: Logic Solution — Plugin Assembly Registration and Steps                   ║
# ╚════════════════════════════════════════════════════════════════════════════════════════╝
#
# Creates Solutions.Logic with plugin assembly reference and SDK message processing steps.
# Expects: $PublisherName, $PublisherPrefix from parent scope.
# Expects: Plugins.Warehouse already built (07-plugins.ps1).
#
# ──────────────────────────────────────────────────────────────────────────────────────────
#                                  Solutions.Logic
# ──────────────────────────────────────────────────────────────────────────────────────────

Write-Host "`n── Solutions.Logic ──" -ForegroundColor Cyan

if (-not (Get-LabValue 'logicSolutionScaffolded')) {

Invoke-LabNative txc workspace component create pp-solution `
    --output "src/Solutions.Logic" `
    --param "PublisherName=$PublisherName" `
    --param "PublisherPrefix=$PublisherPrefix" `
    --param "GeneratePluginAssembly=false"

Write-Host "  ✓ Solutions.Logic" -ForegroundColor Green

# Add Solutions.Logic to the Package Deployer project
cd src/Packages.Main
Invoke-LabNative dotnet add "./Packages.Main.csproj" reference "../Solutions.Logic/Solutions.Logic.csproj"
cd ../..

Write-Host "  ✓ ProjectReference: Logic → Packages.Main" -ForegroundColor Green

# Link plugin project to the logic solution
cd src/Solutions.Logic
Invoke-LabNative dotnet add reference ../Plugins.Warehouse/Plugins.Warehouse.csproj
cd ../..

Write-Host "  ✓ ProjectReference: Plugins.Warehouse → Solutions.Logic" -ForegroundColor Green

# ──────────────────────────────────────────────────────────────────────────────────────────
#                         Plugin Assembly Registration
# ──────────────────────────────────────────────────────────────────────────────────────────

Write-Host "`n── Plugin Assembly & Steps ──" -ForegroundColor Cyan

$assemblyGuid = [guid]::NewGuid()

Invoke-LabNative txc workspace component create pp-plugin-assembly `
    --output "src/Solutions.Logic" `
    --param "AssemblyId=$assemblyGuid" `
    --param "PluginProjectRootPath=../Plugins.Warehouse"

Write-Host "  ✓ Plugin assembly registered" -ForegroundColor Green

# ──────────────────────────────────────────────────────────────────────────────────────────
#                      SDK Message Processing Steps
# ──────────────────────────────────────────────────────────────────────────────────────────

# PreValidation step — ValidateWarehouseTransactionPlugin
# Runs before the DB transaction starts: the cheapest place to reject invalid input.
Invoke-LabNative txc workspace component create pp-plugin-assembly-step `
    --output "src/Solutions.Logic" `
    --param "PrimaryEntity=${PublisherPrefix}_warehousetransaction" `
    --param "PluginProjectName=Plugins.Warehouse" `
    --param "PluginName=ValidateWarehouseTransactionPlugin" `
    --param "Stage=Pre-validation" `
    --param "SdkMessage=Create"


Write-Host "  ✓ Step: ValidateWarehouseTransactionPlugin (Pre-validation, Create)" -ForegroundColor Green

# PostOperation step — SubtractQuantityPlugin
# Runs after the record is written, still inside the transaction: the stock update and
# the transaction record commit or roll back together.
Invoke-LabNative txc workspace component create pp-plugin-assembly-step `
    --output "src/Solutions.Logic" `
    --param "PrimaryEntity=${PublisherPrefix}_warehousetransaction" `
    --param "PluginProjectName=Plugins.Warehouse" `
    --param "PluginName=SubtractQuantityPlugin" `
    --param "Stage=Post-operation" `
    --param "SdkMessage=Create"


Write-Host "  ✓ Step: SubtractQuantityPlugin (Post-operation, Create)" -ForegroundColor Green

# Marks the whole block done — checked instead of Test-Path on the solution csproj so a
# re-run after a partial failure (e.g. solution created but assembly/step registration
# didn't finish) retries everything rather than silently skipping the missing work.
Set-LabValue 'logicSolutionScaffolded' $true

} else {
    Write-Host "  ✓ Solutions.Logic (exists)" -ForegroundColor Green
}

# Older runs built before registering the assembly, leaving a second, stale root
# for the same assembly. Retain the identity declared by its actual source file.
$solutionPath = (Resolve-Path 'src/Solutions.Logic/Other/Solution.xml').Path
[xml]$solution = Get-Content $solutionPath -Raw
foreach ($declaration in Get-ChildItem 'src/Solutions.Logic/PluginAssemblies/*.data.xml') {
    [xml]$assembly = Get-Content $declaration.FullName -Raw
    $name = $assembly.PluginAssembly.FullName.Split(',')[0]
    $id = [guid]$assembly.PluginAssembly.PluginAssemblyId
    foreach ($root in @($solution.SelectNodes("//RootComponent[@type='91']"))) {
        if ($root.schemaName.Split(',')[0] -eq $name -and [guid]$root.id -ne $id) {
            [void]$root.ParentNode.RemoveChild($root)
        }
    }
}
$solution.Save($solutionPath)

# The template has no image parameter; add the minimal pre-image to the generated step.
foreach ($message in @('Update', 'Delete')) {
    $name = "Plugins.Warehouse.SubtractQuantityPlugin: $message of ${PublisherPrefix}_warehousetransaction"
    $existing = @(Get-ChildItem 'src/Solutions.Logic/SdkMessageProcessingSteps/*.xml' | Where-Object {
        ([xml](Get-Content $_.FullName -Raw)).SdkMessageProcessingStep.Name -eq $name
    })
    if ($existing.Count -eq 0) {
        Invoke-LabNative txc @('workspace', 'component', 'create', 'pp-plugin-assembly-step',
        '--output', 'src/Solutions.Logic',
        '--param', "PrimaryEntity=${PublisherPrefix}_warehousetransaction",
        '--param', 'PluginProjectName=Plugins.Warehouse',
        '--param', 'PluginName=SubtractQuantityPlugin',
        '--param', 'Stage=Post-operation', '--param', "SdkMessage=$message")
    }
    $stepFiles = Get-ChildItem 'src/Solutions.Logic/SdkMessageProcessingSteps/*.xml'
    $matched = 0
    foreach ($file in $stepFiles) {
        [xml]$step = Get-Content $file.FullName -Raw
        if ($step.SdkMessageProcessingStep.Name -ne "Plugins.Warehouse.SubtractQuantityPlugin: $message of ${PublisherPrefix}_warehousetransaction") { continue }
        $matched++
        $images = $step.SelectSingleNode('/SdkMessageProcessingStep/SdkMessageProcessingStepImages')
        if (-not $images) { throw "Missing image collection in $($file.Name)." }
        $image = $images.SelectSingleNode("SdkMessageProcessingStepImage[EntityAlias='Before']")
        if (-not $image) {
            $image = $step.CreateElement('SdkMessageProcessingStepImage')
            [void]$images.AppendChild($image)
        }
        # The DevKit schema takes the image id as a child element and enforces this element order.
        $imageId = $image.GetAttribute('SdkMessageProcessingStepImageId')
        if (-not $imageId) { $imageId = $image.SelectSingleNode('SdkMessageProcessingStepImageId')?.InnerText }
        if (-not $imageId) { $imageId = "{$([guid]::NewGuid())}" }
        $image.RemoveAll()
        $image.SetAttribute('Name', 'Before')
        foreach ($pair in ([ordered]@{
            SdkMessageProcessingStepImageId = $imageId
            Attributes ="${PublisherPrefix}_itemid,${PublisherPrefix}_quantity,${PublisherPrefix}_transactiontype"
            EntityAlias = 'Before'; ImageType = '0'; MessagePropertyName = 'Target'; IsCustomizable = '1'
        }).GetEnumerator()) {
            $element = $step.CreateElement($pair.Key)
            $element.InnerText = $pair.Value
            [void]$image.AppendChild($element)
        }
        $step.Save($file.FullName)
    }
    if ($matched -ne 1) { throw "Expected one $message stock-accounting step; found $matched." }
}

foreach ($message in @('Create', 'Update')) {
    $name = "Plugins.Warehouse.ValidateWarehouseTransactionPlugin: $message of ${PublisherPrefix}_warehouseitem"
    $existing = @(Get-ChildItem 'src/Solutions.Logic/SdkMessageProcessingSteps/*.xml' | Where-Object {
        ([xml](Get-Content $_.FullName -Raw)).SdkMessageProcessingStep.Name -eq $name
    })
    if ($existing.Count -gt 1) { throw "Duplicate item stock guards: $name" }
    if ($existing.Count -eq 0) {
        $filterArguments = if ($message -eq 'Update') { @('--param', "FilteringAttributes=${PublisherPrefix}_availablequantity") } else { @() }
        Invoke-LabNative txc workspace component create pp-plugin-assembly-step `
            --output 'src/Solutions.Logic' --param "PrimaryEntity=${PublisherPrefix}_warehouseitem" `
            --param 'PluginProjectName=Plugins.Warehouse' --param 'PluginName=ValidateWarehouseTransactionPlugin' `
            --param 'Stage=Pre-validation' --param "SdkMessage=$message" @filterArguments
    }
}