$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../lib/Lab.Common.ps1"

function Assert-Equal($Expected, $Actual) {
    if ($Expected -ne $Actual) { throw "Expected '$Expected'; got '$Actual'." }
}
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    try { & $Action } catch {
        if ($_.Exception.Message -notlike "*$Message*") { throw }
        return
    }
    throw "Expected failure containing '$Message'."
}

$originalStateFile = $Global:LabStateFile
$temp = New-TemporaryFile
try {
    foreach ($name in @('Invoke-LabNative', 'Assert-LabProfile', 'Wait-LabTestDeployment', 'Get-LabCheckpoints')) {
        Assert-Equal 'Function' (Get-Command $name).CommandType
    }
    Assert-Equal 17 (@(Get-LabCheckpoints).Count)
    Assert-Equal 4 (@((Get-LabCheckpoints | Where-Object Id -eq 'cp11').Tags).Count)
    [xml]$fixtures = Get-Content "$PSScriptRoot/../templates/13-config-data/data.xml" -Raw
    $balances = @{}
    foreach ($record in ($fixtures.entities.entity | Where-Object name -eq '__PREFIX___warehouseitem').records.record) {
        $balances[$record.id] = [int]($record.field | Where-Object name -eq '__PREFIX___availablequantity').value
    }
    foreach ($record in ($fixtures.entities.entity | Where-Object name -eq '__PREFIX___warehousetransaction').records.record) {
        $item = ($record.field | Where-Object name -eq '__PREFIX___itemid').value
        $quantity = [int]($record.field | Where-Object name -eq '__PREFIX___quantity').value
        $type = ($record.field | Where-Object name -eq '__PREFIX___transactiontype').value
        if ($quantity -le 0) { throw 'Fixture movement must be positive.' }
        $balances[$item] -= $quantity * $(if ($type -eq '100000000') { 1 } else { -1 })
    }
    foreach ($balance in $balances.Values) { Assert-Equal 0 $balance }
    function gh {
        $global:LASTEXITCODE = 0
        $script:policy | ConvertTo-Json
    }
    $script:policy = @{ use_default = $true }
    Assert-Equal 'repo:learner/alm-lab:ref:refs/heads/main' (Get-LabOidcSubject 'learner/alm-lab')
    $script:policy = @{ use_default = $true; use_immutable_subject = $true; sub_claim_prefix = 'repo:learner@123/alm-lab@456' }
    Assert-Equal 'repo:learner@123/alm-lab@456:ref:refs/heads/main' (Get-LabOidcSubject 'learner/alm-lab')
    $script:policy = @{ use_default = $true; use_immutable_subject = $true }
    Assert-Throws { Get-LabOidcSubject 'learner/alm-lab' } 'immutable OIDC'
    $script:policy = @{ use_default = $false }
    Assert-Throws { Get-LabOidcSubject 'learner/alm-lab' } 'Custom OIDC'
    Remove-Item function:gh

    function git { $global:LASTEXITCODE = 0; $script:origin }
    $script:origin = 'git@github.com:learner/alm-lab.git'
    Assert-Equal 'learner/alm-lab' (Get-LabRepository)
    $script:origin = 'https://github.com/learner/alm-lab.git'
    Assert-Equal 'learner/alm-lab' (Get-LabRepository)
    $script:origin = 'https://github.com/TALXIS/alm-lab.git'
    Assert-Throws { Get-LabRepository } 'own fork'
    Remove-Item function:git

    Assert-Equal 'value with spaces' (Invoke-LabNative git -c 'lab.test=value with spaces' config lab.test)
    Assert-Equal 'array' (Invoke-LabNative git @('-c', 'lab.test=array', 'config', 'lab.test'))
    Assert-Throws { Invoke-LabNative pwsh @('-NoProfile', '-NonInteractive', '-Command', 'exit 9') } 'exit 9'
    $Global:LabStateFile = $temp.FullName
    Set-Content $temp.FullName '{broken'
    Assert-Throws { Import-LabState } 'Cannot read'
    Set-Content $temp.FullName '[]'
    Assert-Throws { Import-LabState } 'Expected a JSON object'
    Set-Content $temp.FullName '{"slnxName":"WarehouseManagement"}'
    Import-LabState | Out-Null
    Assert-Equal 'WarehouseManagement' (Get-LabValue 'slnxName')

    foreach ($file in Get-ChildItem "$PSScriptRoot/.." -Recurse -Filter '*.ps1') {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        if ($errors.Count) { throw "$($file.FullName): $errors" }
    }
    Write-Host 'Lab helpers and PowerShell syntax passed.'
} finally {
    $Global:LabStateFile = $originalStateFile
    Remove-Item $temp.FullName
}
