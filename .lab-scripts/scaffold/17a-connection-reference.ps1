$referenceName = "${PublisherPrefix}_openfoodfacts"
$connectorPackage = Get-ChildItem "$LabRoot/src/Solutions.Connectors/bin/Debug" -Recurse -Filter 'Solutions.Connectors.zip' | Select-Object -First 1
if (-not $connectorPackage) { throw 'Build Solutions.Connectors in Debug before creating its connection reference.' }
$archive = [IO.Compression.ZipFile]::OpenRead($connectorPackage.FullName)
try {
    $reader = [IO.StreamReader]::new($archive.GetEntry('customizations.xml').Open())
    try { [xml]$packed = $reader.ReadToEnd() } finally { $reader.Dispose() }
    $connector = $packed.SelectSingleNode("/ImportExportXml/Connectors/Connector[name='${PublisherPrefix}_connectorsopenfoodfacts']")
    if (-not $connector) { throw 'The built solution does not contain the expected connector.' }
    $connectorGuid = $connector.connectorid
} finally { $archive.Dispose() }
if (-not [guid]::TryParse($connectorGuid, [ref]([guid]::Empty))) { throw 'Connector descriptor has no valid identity.' }

$devBinding = $null
if ($env:LAB_LOCAL_MODE -eq '1') {
    $apiId = "shared_${PublisherPrefix}_connectorsopenfoodfacts"
} else {
    $devBinding = Get-LabConnectorConnection dev
    $apiId = $devBinding.ConnectorId
}
$customizationsPath = "$LabRoot/src/Solutions.Connectors/Other/Customizations.xml"
[xml]$customizations = Get-Content $customizationsPath -Raw
$references = $customizations.SelectSingleNode('/ImportExportXml/connectionreferences')
if (-not $references) {
    $references = $customizations.CreateElement('connectionreferences')
    [void]$customizations.DocumentElement.AppendChild($references)
}
$reference = $references.SelectSingleNode("connectionreference[@connectionreferencelogicalname='$referenceName']")
if (-not $reference) {
    $reference = $customizations.CreateElement('connectionreference')
    $reference.SetAttribute('connectionreferencelogicalname', $referenceName)
    [void]$references.AppendChild($reference)
} else {
    foreach ($child in @($reference.ChildNodes)) { [void]$reference.RemoveChild($child) }
}
foreach ($field in ([ordered]@{
    connectionreferencedisplayname = 'Open Food Facts'
    connectorid = "/providers/Microsoft.PowerApps/apis/$apiId"
    customconnectorid = $connectorGuid
    iscustomizable = '1'; promptingbehavior = '0'; statecode = '0'; statuscode = '1'
}).GetEnumerator()) {
    $node = $customizations.CreateElement($field.Key)
    if ($field.Key -eq 'customconnectorid') {
        $lookup = $customizations.CreateElement('connectorid')
        $lookup.InnerText = $field.Value
        [void]$node.AppendChild($lookup)
    } else { $node.InnerText = $field.Value }
    [void]$reference.AppendChild($node)
}
$customizations.Save($customizationsPath)

if ($env:LAB_LOCAL_MODE -ne '1') {
    Invoke-LabNative dotnet build "$LabRoot/src/Solutions.Connectors/Solutions.Connectors.csproj" -c Debug --nologo --verbosity quiet
    $connectorPackage = Get-ChildItem "$LabRoot/src/Solutions.Connectors/bin/Debug" -Recurse -Filter 'Solutions.Connectors.zip' | Select-Object -First 1
    Invoke-LabNative txc env pkg import $connectorPackage.FullName --profile (Get-LabValue 'devProfile')
    & "$LabRoot/.lab-scripts/Set-LabConnectionReference.ps1" -Profile (Get-LabValue 'devProfile') `
        -LogicalName $referenceName -ConnectorId $devBinding.ConnectorId -ConnectionId $devBinding.ConnectionId

    # Stage 2 already promoted the connector. Connection consent is interactive here,
    # never hidden inside a headless deployment job.
    Wait-LabTestDeployment
    $testBinding = Get-LabConnectorConnection test
    $repo = Get-LabRepository
    Invoke-LabNative gh variable set OPENFOODFACTS_TEST_CONNECTION_ID --repo $repo --body $testBinding.ConnectionId
    Invoke-LabNative gh variable set OPENFOODFACTS_TEST_CONNECTOR_ID --repo $repo --body $testBinding.ConnectorId
}
