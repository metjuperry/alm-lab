$ErrorActionPreference = 'Stop'
$global:LabTestCalls = @()
function txc {
    $global:LASTEXITCODE = 0
    $global:LabTestCalls += ,@($args)
    if ($args -contains 'query') {
        '[{"connectionreferenceid":"11111111-1111-4111-8111-111111111111"}]'
    }
}
& "$PSScriptRoot/../Set-LabConnectionReference.ps1" -Profile ci -LogicalName almlab_openfoodfacts `
    -ConnectionId 'test-connection' -ConnectorId 'shared_test_connector'
if ($global:LabTestCalls.Count -ne 2) { throw 'Expected one lookup and one update.' }
$update = $global:LabTestCalls[1]
if ($update[$update.IndexOf('--profile') + 1] -ne 'ci') { throw 'Wrong target profile.' }
$data = $update[$update.IndexOf('--data') + 1] | ConvertFrom-Json
if ($data.connectionid -ne 'test-connection' -or $data.connectorid -ne '/providers/Microsoft.PowerApps/apis/shared_test_connector') {
    throw 'Target-specific connection mapping was lost.'
}
function txc { $global:LASTEXITCODE = 0; '[]' }
$failed = $false
try {
    & "$PSScriptRoot/../Set-LabConnectionReference.ps1" -Profile ci -LogicalName almlab_openfoodfacts `
        -ConnectionId 'test-connection' -ConnectorId 'shared_test_connector'
} catch {
    if ($_.Exception.Message -notlike '*Expected one imported*') { throw }
    $failed = $true
}
if (-not $failed) { throw 'Missing imported reference must fail, not create an unmanaged substitute.' }
Write-Host 'Connection reference mapping and missing-definition guard passed.'
Remove-Variable LabTestCalls -Scope Global
