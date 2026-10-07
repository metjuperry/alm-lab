$ErrorActionPreference = 'Stop'
$directory = Join-Path ([IO.Path]::GetTempPath()) "lab-pack-test-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory $directory | Out-Null
try {
    $declared = [guid]::NewGuid().ToString()
    foreach ($valid in @($true, $false)) {
        $actual = if ($valid) { $declared } else { [guid]::NewGuid().ToString() }
        $path = Join-Path $directory "$valid.zip"
        $zip = [IO.Compression.ZipFile]::Open($path, [IO.Compression.ZipArchiveMode]::Create)
        try {
            $entries = @{
                'solution.xml' = "<ImportExportXml><SolutionManifest><RootComponents><RootComponent type='60' id='{$declared}' /></RootComponents></SolutionManifest></ImportExportXml>"
                'customizations.xml' = "<ImportExportXml><Entities><Entity><FormXml><forms><systemform><formid>{$actual}</formid></systemform></forms></FormXml></Entity></Entities></ImportExportXml>"
            }
            foreach ($entry in $entries.GetEnumerator()) {
                $writer = [IO.StreamWriter]::new($zip.CreateEntry($entry.Key).Open())
                try { $writer.Write($entry.Value) } finally { $writer.Dispose() }
            }
        } finally { $zip.Dispose() }
        $rejected = $false
        try { & "$PSScriptRoot/../build/PackSolution.ps1" -ZipPath $path -ValidateOnly }
        catch {
            if ($_.Exception.Message -notlike '*absent from the packed customizations*') { throw }
            $rejected = $true
        }
        if ($rejected -eq $valid) { throw "Archive validation returned the wrong result for valid=$valid." }
        Remove-Item $path
    }
    Write-Host 'Archive validation accepts present forms and rejects missing forms.'
} finally { Remove-Item $directory }
