[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Package,
    [switch]$Complete,
    [ValidateSet('Managed', 'Unmanaged')][string]$Mode = 'Managed'
)
$ErrorActionPreference = 'Stop'
function Read-ZipXml($Archive, [string]$Name) {
    $entry = $Archive.GetEntry($Name)
    if (-not $entry) { throw "Package is missing $Name." }
    $reader = [IO.StreamReader]::new($entry.Open())
    try { return [xml]$reader.ReadToEnd() } finally { $reader.Dispose() }
}
$archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path $Package))
try {
    $config = Read-ZipXml $archive 'PkgAssets/ImportConfig.xml'
    $files = @($config.SelectNodes('//configsolutionfile') | ForEach-Object { $_.solutionpackagefilename })
    if (-not $files.Count) { throw 'The deployment package contains no solutions.' }
    $expected = @('Solutions.DataModel.zip', 'Solutions.Logic.zip', 'Solutions.Security.zip', 'Solutions.Connectors.zip', 'Solutions.UI.zip')
    if ($Complete) {
        foreach ($name in $expected) {
            if ($name -notin $files) { throw "The complete app is missing $name." }
        }
        if ([array]::IndexOf($files, 'Solutions.Connectors.zip') -gt [array]::IndexOf($files, 'Solutions.UI.zip')) {
            throw 'The connector/reference must import before its consuming UI.'
        }
        if (-not $archive.GetEntry('PkgAssets/MainCmtPackage.zip')) { throw 'The final package is missing its grocery configuration data.' }
    }
    foreach ($name in $files) {
        $entry = $archive.GetEntry("PkgAssets/$name")
        if (-not $entry) { throw "ImportConfig references absent solution $name." }
        $stream = [IO.MemoryStream]::new()
        $inputStream = $entry.Open()
        try { $inputStream.CopyTo($stream) } finally { $inputStream.Dispose() }
        $stream.Position = 0
        $nested = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read)
        try {
            $solution = Read-ZipXml $nested 'solution.xml'
            $metadata = Read-ZipXml $nested 'customizations.xml'
            $managed = $solution.SelectSingleNode('//Managed').InnerText
            if ($managed -ne $(if ($Mode -eq 'Managed') { '1' } else { '0' })) { throw "$name has the wrong managed state." }
            if (-not $Complete) { continue }
            switch ($name) {
                'Solutions.DataModel.zip' {
                    foreach ($suffix in @('warehouseitem','warehouselocation','warehousetransaction','product')) {
                        if (-not ($metadata.SelectNodes('//Entities/Entity/Name') | Where-Object InnerText -Like "*_$suffix")) {
                            throw "The generated model is missing $suffix."
                        }
                    }
                }
                'Solutions.Logic.zip' {
                    foreach ($message in @('Create','Update','Delete')) {
                        $steps = @($metadata.SelectNodes('//SdkMessageProcessingStep') | Where-Object { $_.Name -like "*SubtractQuantityPlugin: $message of *" })
                        if ($steps.Count -ne 1 -or $steps[0].Stage -ne '40' -or $steps[0].Mode -ne '0') {
                            throw "Expected one synchronous post-operation stock step for $message."
                        }
                        if ($message -ne 'Create' -and -not $steps[0].SelectSingleNode(".//SdkMessageProcessingStepImage[EntityAlias='Before']")) {
                            throw "$message accounting has no pre-image."
                        }
                    }
                    if (-not ($nested.Entries | Where-Object FullName -Like 'PluginAssemblies/*.dll')) { throw 'The plugin binary is missing.' }
                }
                'Solutions.Security.zip' {
                    foreach ($role in @('Warehouse worker','Warehouse manager')) {
                        if (-not ($metadata.SelectNodes('//Role') | Where-Object name -eq $role)) { throw "Missing role $role." }
                    }
                }
                'Solutions.Connectors.zip' {
                    if (-not $metadata.SelectSingleNode('//Connectors/Connector')) { throw 'The connector solution is empty.' }
                    if (-not $metadata.SelectSingleNode('//connectionreference')) { throw 'The portable connection reference is missing.' }
                    if (-not ($nested.Entries | Where-Object FullName -Like 'Connector/*_openapidefinition.json')) { throw 'The connector API definition is missing.' }
                }
                'Solutions.UI.zip' {
                    if (-not $metadata.SelectSingleNode('//AppModule')) { throw 'The model-driven app is missing.' }
                    if (-not $metadata.SelectSingleNode('//CanvasApp')) { throw 'The picking code app is missing.' }
                    if ($metadata.SelectSingleNode('//*[@GenPageId]')) { throw 'The core app still navigates to an optional dashboard.' }
                }
            }
        } finally { $nested.Dispose(); $stream.Dispose() }
    }
    Write-Host "Verified $Mode deployment package: $($files -join ', ')."
} finally { $archive.Dispose() }
