# Intended for the disposable devcontainer. Running manually changes this user's
# global CLI tools and template registry; it does not authenticate to any service.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/lib/Lab.Common.ps1"
$versions = Get-Content "$PSScriptRoot/toolchain.json" -Raw | ConvertFrom-Json
Invoke-LabNative dotnet tool update --global TALXIS.CLI --version $versions.txc --allow-downgrade
Invoke-LabNative dotnet new install "TALXIS.DevKit.Templates.Dataverse::$($versions.templates)" --force
Invoke-LabNative npm install --global "@microsoft/power-apps-cli@$($versions.paMinimum)"
Write-Ok 'Pinned CLI and templates installed. CP01 verifies the complete toolchain.'
