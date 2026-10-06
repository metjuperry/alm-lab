#
# ╔════════════════════════════════════════════════════════════════════════════════════════╗
# ║           05a: UI Solution — Project, Entity Refs, App, App Components                 ║
# ╚════════════════════════════════════════════════════════════════════════════════════════╝
#
# Creates Solutions.UI with existing entity references, a model-driven app,
# and entity app components.
# Expects: $PublisherName, $PublisherPrefix from parent scope.
#
# ──────────────────────────────────────────────────────────────────────────────────────────
#                                    Solutions.UI
# ──────────────────────────────────────────────────────────────────────────────────────────

Write-Host "`n── Solutions.UI ──" -ForegroundColor Cyan

if (-not (Get-LabValue 'uiSolutionScaffolded')) {
    Invoke-LabNative txc workspace component create pp-solution `
        --output "src/Solutions.UI" `
        --param "PublisherName=$PublisherName" `
        --param "PublisherPrefix=$PublisherPrefix"

    Write-Host "  ✓ Solutions.UI" -ForegroundColor Green

    # Add Solutions.UI to the Package Deployer project as a .NET ProjectReference
    cd src/Packages.Main
    Invoke-LabNative dotnet add "./Packages.Main.csproj" reference "../Solutions.UI/Solutions.UI.csproj"
    cd ../..

    Write-Host "  ✓ ProjectReference: UI → Packages.Main" -ForegroundColor Green

    # ──────────────────────────────────────────────────────────────────────────────────────
    #                              Existing Entity References
    # ──────────────────────────────────────────────────────────────────────────────────────

    Write-Host "`n── Entity References (UI) ──" -ForegroundColor Cyan

    # Behavior=Existing creates a reference, not a table: the schema stays owned by
    # Solutions.DataModel; this solution only layers UI (forms, views, ribbon) on top of it.

    Invoke-LabNative txc workspace component create pp-entity `
        --output "src/Solutions.UI" `
        --param "Behavior=Existing" `
        --param "PublisherPrefix=$PublisherPrefix" `
        --param "LogicalName=warehouselocation" `
        --param "DisplayName=Warehouse Location"

    Write-Host "  ✓ Entity ref: Warehouse Location" -ForegroundColor Green

    Invoke-LabNative txc workspace component create pp-entity `
        --output "src/Solutions.UI" `
        --param "Behavior=Existing" `
        --param "PublisherPrefix=$PublisherPrefix" `
        --param "LogicalName=warehouseitem" `
        --param "DisplayName=Warehouse Item"

    Write-Host "  ✓ Entity ref: Warehouse Item" -ForegroundColor Green

    Invoke-LabNative txc workspace component create pp-entity `
        --output "src/Solutions.UI" `
        --param "Behavior=Existing" `
        --param "PublisherPrefix=$PublisherPrefix" `
        --param "LogicalName=warehousetransaction" `
        --param "DisplayName=Warehouse Transaction"

    Write-Host "  ✓ Entity ref: Warehouse Transaction" -ForegroundColor Green

    # ──────────────────────────────────────────────────────────────────────────────────────
    #                                  Model-Driven App
    # ──────────────────────────────────────────────────────────────────────────────────────

    Write-Host "`n── Model-Driven App ──" -ForegroundColor Cyan

    Invoke-LabNative txc workspace component create pp-app-model `
        --output "src/Solutions.UI" `
        --param "PublisherPrefix=$PublisherPrefix" `
        --param "LogicalName=warehouseapp"

    Write-Host "  ✓ App: warehouseapp" -ForegroundColor Green

    # ──────────────────────────────────────────────────────────────────────────────────────
    #                                  App Components
    # ──────────────────────────────────────────────────────────────────────────────────────

    Write-Host "`n── App Components ──" -ForegroundColor Cyan

    Invoke-LabNative txc workspace component create pp-app-model-component `
        --output "src/Solutions.UI" `
        --param "EntityLogicalName=${PublisherPrefix}_warehouselocation" `
        --param "AppName=${PublisherPrefix}_warehouseapp"

    Write-Host "  ✓ App component: warehouselocation" -ForegroundColor Green

    Invoke-LabNative txc workspace component create pp-app-model-component `
        --output "src/Solutions.UI" `
        --param "EntityLogicalName=${PublisherPrefix}_warehouseitem" `
        --param "AppName=${PublisherPrefix}_warehouseapp"

    Write-Host "  ✓ App component: warehouseitem" -ForegroundColor Green

    Invoke-LabNative txc workspace component create pp-app-model-component `
        --output "src/Solutions.UI" `
        --param "EntityLogicalName=${PublisherPrefix}_warehousetransaction" `
        --param "AppName=${PublisherPrefix}_warehouseapp"

    Write-Host "  ✓ App component: warehousetransaction" -ForegroundColor Green

    $roleIds = @(Get-ChildItem 'src/Solutions.Security/Roles/*.xml' | ForEach-Object {
        ([xml](Get-Content $_.FullName -Raw)).Role.id.Trim('{}')
    })
    # pp-app-security-role currently imports an AppModuleRoles node it never generates.
    # Write the verified RoleMaps contract rather than leaving inaccessible app defaults.
    $appPath = "src/Solutions.UI/AppModules/${PublisherPrefix}_warehouseapp/AppModule.xml"
    [xml]$app = Get-Content $appPath -Raw
    $maps = $app.SelectSingleNode('/AppModule/AppModuleRoleMaps')
    if (-not $maps) {
        $maps = $app.CreateElement('AppModuleRoleMaps')
        [void]$app.DocumentElement.AppendChild($maps)
    }
    $maps.RemoveAll()
    foreach ($id in $roleIds) {
        $role = $app.CreateElement('Role')
        $role.SetAttribute('id', "{$id}")
        [void]$maps.AppendChild($role)
    }
    $app.Save((Resolve-Path $appPath).Path)

    # Marks the whole block done — checked instead of Test-Path on the solution csproj so a
    # re-run after a partial failure (e.g. solution created but the app/components didn't
    # finish) retries everything rather than silently skipping the missing work.
    Set-LabValue 'uiSolutionScaffolded' $true
} else {
    Write-Host "  ✓ Solutions.UI (exists)" -ForegroundColor Green
}
