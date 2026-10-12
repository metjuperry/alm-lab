param([Parameter(Mandatory)][string]$MetadataDirectory)
$ErrorActionPreference = 'Stop'
$solutionXml = Join-Path $MetadataDirectory 'Other/Solution.xml'
if (-not (Test-Path $solutionXml)) { return }
[xml]$xml = Get-Content $solutionXml -Raw
foreach ($root in @($xml.SelectNodes("//RootComponent[@type='29']"))) { [void]$root.ParentNode.RemoveChild($root) }
$xml.Save($solutionXml)
