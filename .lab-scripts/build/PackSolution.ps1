[CmdletBinding()]
param(
    [ValidateSet('Pack', 'Unpack')][string]$Action = 'Pack',
    [string]$SourceDirectory,
    [Parameter(Mandatory)][string]$ZipPath,
    [ValidateSet('Managed', 'Unmanaged', 'Both')][string]$PackageType = 'Unmanaged',
    [string]$LogPath,
    [string]$MapPath,
    [string]$SourceLocale,
    [switch]$Localize,
    [switch]$UseUnmanagedFileForMissingManaged,
    [switch]$ValidateOnly
)
$ErrorActionPreference = 'Stop'
$zip = [IO.Path]::GetFullPath($ZipPath)
$output = ''
try {
    if (-not $ValidateOnly) {
        $arguments = @('tool', 'run', 'pac', '--', 'solution', $Action.ToLowerInvariant(),
            '--folder', $SourceDirectory, '--zipfile', $zip, '--packagetype', $PackageType)
        if ($LogPath) { $arguments += @('--log', $LogPath) }
        if ($MapPath) { $arguments += @('--map', $MapPath) }
        if ($SourceLocale) { $arguments += @('--sourceLoc', $SourceLocale) }
        if ($Localize) { $arguments += '--localize' }
        if ($UseUnmanagedFileForMissingManaged) { $arguments += '--useUnmanagedFileForMissingManaged' }
        $output = (& dotnet @arguments 2>&1 | Out-String)
        Write-Host $output
        if ($LASTEXITCODE -ne 0) { throw "PAC $Action failed (exit $LASTEXITCODE)." }
    }
    if ($Action -eq 'Unpack') { return }

    $archive = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        function Read-ArchiveXml([string]$Name) {
            $entry = $archive.GetEntry($Name)
            if (-not $entry) { throw "Missing $Name in $zip." }
            $reader = [IO.StreamReader]::new($entry.Open())
            try { return [xml]$reader.ReadToEnd() } finally { $reader.Dispose() }
        }
        $solution = Read-ArchiveXml 'solution.xml'
        $customizations = Read-ArchiveXml 'customizations.xml'
        $forms = @{}
        foreach ($form in $customizations.SelectNodes('//systemform/formid')) {
            $forms[([guid]$form.InnerText).ToString()] = $true
        }
        $connectors = @{}
        foreach ($connector in $customizations.SelectNodes('//*[translate(local-name(), "CONNECTOR", "connector")="connector"]')) {
            foreach ($attribute in $connector.Attributes) { $connectors[$attribute.Value] = $true }
            $name = $connector.SelectSingleNode('name')
            if ($name) { $connectors[$name.InnerText] = $true }
            foreach ($field in @('openapidefinition', 'connectionparameters', 'policytemplateinstances', 'customcodeblobcontent')) {
                $reference = $connector.SelectSingleNode($field)
                if ($reference -and $reference.InnerText -and -not $archive.GetEntry($reference.InnerText.TrimStart('/'))) {
                    throw "Connector payload file is missing: $($reference.InnerText)"
                }
            }
        }
        foreach ($component in $solution.SelectNodes('//RootComponent')) {
            if ($component.type -eq '60' -and -not $forms.ContainsKey(([guid]$component.id).ToString())) {
                throw "Declared form $($component.id) is absent from the packed customizations."
            }
            if ($component.type -in @('371', '372') -and -not $connectors.ContainsKey($component.schemaName)) {
                throw "Declared connector $($component.schemaName) is absent from the packed customizations."
            }
        }
        foreach ($match in [regex]::Matches($output, "Type='([^']+)',\s*Id \(or schema name\)='([^']+)'")) {
            $type = $match.Groups[1].Value
            $id = $match.Groups[2].Value
            $verified = ($type -eq 'SystemForm' -and $forms.ContainsKey(([guid]$id).ToString())) -or
                ($type -eq 'ECConnector' -and $connectors.ContainsKey(($id -replace '^ECConnector-', '')))
            if (-not $verified) { throw "Unresolved packed root component: $type $id" }
            Write-Host "Verified packed payload for reported $type $id."
        }
    } finally { $archive.Dispose() }
}
catch {
    if (-not $ValidateOnly -and $Action -eq 'Pack' -and [IO.File]::Exists($zip)) { [IO.File]::Delete($zip) }
    throw
}
