[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Profile,
    [Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9_]*$')][string]$LogicalName,
    [Parameter(Mandatory)][string]$ConnectorId,
    [Parameter(Mandatory)][string]$ConnectionId
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/lib/Lab.Common.ps1"
$references = @(Invoke-LabNative txc env data query odata connectionreferences `
    --select connectionreferenceid --filter "connectionreferencelogicalname eq '$LogicalName'" `
    --profile $Profile --format json | ConvertFrom-Json)
if ($references.Count -ne 1) { throw "Expected one imported $LogicalName reference in $Profile; found $($references.Count)." }
$connector = if ($ConnectorId.StartsWith('/providers/')) { $ConnectorId } else { "/providers/Microsoft.PowerApps/apis/$ConnectorId" }
$data = @{ connectionid = $ConnectionId; connectorid = $connector } | ConvertTo-Json -Compress
Invoke-LabNative txc env data record update $references[0].connectionreferenceid `
    --entity connectionreference --data $data --apply --profile $Profile
Write-Ok "Bound $LogicalName in $Profile to its own environment's connection."
