#
# ╔════════════════════════════════════════════════════════════════════════════════════════╗
# ║                  07: Plugins — Plugin Project and Plugin Classes                       ║
# ╚════════════════════════════════════════════════════════════════════════════════════════╝
#
# Creates the Plugins.Warehouse project with signing key and two plugin classes:
# - ValidateWarehouseTransactionPlugin (PreValidation on Create)
# - SubtractQuantityPlugin (PostOperation on Create)
#
# Expects: $PublisherName, $PublisherPrefix, $SolutionName from parent scope.
#
# ──────────────────────────────────────────────────────────────────────────────────────────
#                              Plugin Project
# ──────────────────────────────────────────────────────────────────────────────────────────

if (-not (Get-LabValue 'pluginsScaffolded')) {

Invoke-LabNative txc workspace component create pp-plugin `
    --output "src/Plugins.Warehouse" `
    --param "PublisherName=$PublisherName" `
    --param "Company=$PublisherName"

Invoke-LabNative dotnet sln add src/Plugins.Warehouse

Write-Host "  ✓ Plugins.Warehouse project" -ForegroundColor Green

# ──────────────────────────────────────────────────────────────────────────────────────────
#                         ValidateWarehouseTransactionPlugin.cs
# ──────────────────────────────────────────────────────────────────────────────────────────

# Full source: .lab-scripts/templates/07-plugins/ValidateWarehouseTransactionPlugin.cs
Expand-LabTemplate -Path "07-plugins/ValidateWarehouseTransactionPlugin.cs" `
    -Destination "src/Plugins.Warehouse/ValidateWarehouseTransactionPlugin.cs" `
    -Tokens @{ PREFIX = $PublisherPrefix }
Write-Host "  ✓ ValidateWarehouseTransactionPlugin.cs" -ForegroundColor Green

# ──────────────────────────────────────────────────────────────────────────────────────────
#                            SubtractQuantityPlugin.cs
# ──────────────────────────────────────────────────────────────────────────────────────────

# Full source: .lab-scripts/templates/07-plugins/SubtractQuantityPlugin.cs
Expand-LabTemplate -Path "07-plugins/SubtractQuantityPlugin.cs" `
    -Destination "src/Plugins.Warehouse/SubtractQuantityPlugin.cs" `
    -Tokens @{ PREFIX = $PublisherPrefix }
Write-Host "  ✓ SubtractQuantityPlugin.cs" -ForegroundColor Green
Expand-LabTemplate -Path "07-plugins/WarehouseStock.cs" `
    -Destination "src/Plugins.Warehouse/WarehouseStock.cs" `
    -Tokens @{ PREFIX = $PublisherPrefix }

# ──────────────────────────────────────────────────────────────────────────────────────────
#                              Build Plugin Project
# ──────────────────────────────────────────────────────────────────────────────────────────

Write-Host "  → Building Plugins.Warehouse..." -ForegroundColor White
cd src/Plugins.Warehouse
Invoke-LabNative dotnet build --nologo --verbosity quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ Plugin build succeeded" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Plugin build had issues (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
}

Invoke-LabNative dotnet publish --nologo --verbosity quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ Plugin publish succeeded" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Plugin publish had issues (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
}
cd ../..

# Marks the whole block done — checked instead of Test-Path on the csproj so a re-run after
# a partial failure (e.g. project created but a plugin class/build step didn't finish)
# retries everything rather than silently skipping the missing work.
Set-LabValue 'pluginsScaffolded' $true

} else {
    Write-Host "  ✓ Plugins.Warehouse (exists)" -ForegroundColor Green
}
