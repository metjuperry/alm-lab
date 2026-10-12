#
# ╔════════════════════════════════════════════════════════════════════════════════════════╗
# ║                          Lab.Common.ps1 — shared helpers                               ║
# ╚════════════════════════════════════════════════════════════════════════════════════════╝
#
# Dot-source this file at the top of every checkpoint:  . "$PSScriptRoot/lib/Lab.Common.ps1"
#
# It provides:
#   - Lab state persistence (.lab-state.json, committed to the repo) so your variables
#     survive terminal/Codespaces crashes and you can resume from any checkpoint.
#   - A random identifier so attendees don't clash on names in the shared training tenant.
#   - Logging helpers and a Save-Checkpoint function that commits, pushes and tags.
#
# ──────────────────────────────────────────────────────────────────────────────────────────

# Repo root = parent of .lab-scripts
$Global:LabRoot      = (Resolve-Path "$PSScriptRoot/../..").Path
$Global:LabStateFile = Join-Path $LabRoot ".lab-state.json"

# The agentbox image bakes a pinned, older txc into /usr/local/bin for fast startup and relies
# on the devcontainer's remoteEnv/postStartCommand to shadow it with a freshly-updated global
# tool on every container start - but that only happens under the actual devcontainer/Codespaces
# lifecycle. Running the image directly (this repo's LOCAL-DRY-RUN.md, CI) never triggers it, so
# every checkpoint has to assert the same PATH precedence itself, in its own process, rather than
# relying on a single earlier checkpoint (or the devcontainer) having already done it.
$env:PATH = "$HOME/.dotnet/tools:$env:PATH"

# ── Logging ────────────────────────────────────────────────────────────────────────────────
function Write-Step  { param([string]$m) Write-Host "`n── $m ──" -ForegroundColor Cyan }
function Write-Ok    { param([string]$m) Write-Host "  ✓ $m" -ForegroundColor Green }
function Write-Warn2 { param([string]$m) Write-Host "  ⚠ $m" -ForegroundColor Yellow }
function Write-Err   { param([string]$m) Write-Host "  ✗ $m" -ForegroundColor Red }
function Write-Info  { param([string]$m) Write-Host "  $m" -ForegroundColor Gray }

# ── State load/save ──────────────────────────────────────────────────────────────────────
# State is a flat hashtable stored as JSON in the repo. Loaded into $Global:Lab.
function Import-LabState {
    if (Test-Path $LabStateFile) {
        $raw = Get-Content -Raw -Path $LabStateFile
        try {
            $Global:Lab = $raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            if ($Global:Lab -isnot [System.Collections.IDictionary]) { throw "Expected a JSON object." }
        } catch {
            throw "Cannot read $LabStateFile. Restore a valid state file before continuing: $_"
        }
    } else {
        $Global:Lab = @{}
    }
    return $Global:Lab
}

function Save-LabState {
    $Global:Lab | ConvertTo-Json -Depth 10 | Set-Content -Path $LabStateFile -Encoding UTF8
}

function Set-LabValue {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Value)
    if (-not $Global:Lab) { Import-LabState }
    $Global:Lab[$Name] = $Value
    Save-LabState
}

function Get-LabValue {
    param([Parameter(Mandatory)][string]$Name, $Default = $null)
    if (-not $Global:Lab) { Import-LabState }
    if ($Global:Lab.ContainsKey($Name)) { return $Global:Lab[$Name] }
    return $Default
}

# Seed the random identifier once; reused for all unique names in the shared tenant.
function Initialize-RandomIdentifier {
    if (-not (Get-LabValue 'randomIdentifier')) {
        Set-LabValue 'randomIdentifier' (Get-Random -Minimum 1000 -Maximum 9999)
    }
    return (Get-LabValue 'randomIdentifier')
}

function Invoke-LabNative {
    # Native -c/-o flags must not bind PowerShell's Command/common parameters.
    # Accept both a native argument list and an explicitly supplied array.
    if ($args.Count -eq 0) { throw 'A native command is required.' }
    $Command = [string]$args[0]
    [string[]]$Arguments = @($args | Select-Object -Skip 1 | ForEach-Object { $_ })
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command failed (exit $LASTEXITCODE). Check the output above; no checkpoint was completed." }
}

function Get-LabRepository {
    $origin = Invoke-LabNative git @('-C', $LabRoot, 'remote', 'get-url', 'origin')
    if ($origin -notmatch '^https://github\.com/(.+?)(?:\.git)?$|^git@github\.com:(.+?)(?:\.git)?$') {
        throw "Origin must be your GitHub fork (HTTPS or SSH)."
    }
    $repo = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
    if ($repo -eq 'TALXIS/alm-lab') { throw "Create your own fork before running checkpoints." }
    return $repo
}

function Get-LabOidcSubject {
    param([Parameter(Mandatory)][string]$Repository)
    $policy = Invoke-LabNative gh @('api', "repos/$Repository/actions/oidc/customization/sub") | ConvertFrom-Json
    if (-not $policy.use_default) {
        throw "Custom OIDC claim templates are not supported by this lab. Review the repository subject policy before configuring federation."
    }
    $prefix = if ($policy.sub_claim_prefix) { $policy.sub_claim_prefix } else { "repo:$Repository" }
    if ($policy.use_immutable_subject -and -not $policy.sub_claim_prefix) {
        throw "GitHub did not return the immutable OIDC subject prefix."
    }
    return "${prefix}:ref:refs/heads/main"
}

function Assert-LabProfile {
    param([Parameter(Mandatory)][ValidateSet('dev', 'test')][string]$Target)
    if ($env:LAB_LOCAL_MODE -eq '1') { return }
    $name = Get-LabValue "${Target}Profile"
    $url = Get-LabValue "${Target}EnvUrl"
    if (-not $name -or -not $url -or $url -like '*.stub.invalid*') { throw "Run CP04 first: $Target target is missing or belongs to a dry run." }
    $profiles = Invoke-LabNative txc @('config', 'profile', 'list', '--format', 'json') | ConvertFrom-Json
    $profile = $profiles | Where-Object id -eq $name
    if (-not $profile) { throw "Profile '$name' is missing on this machine. Re-run CP04." }
    $connections = Invoke-LabNative txc config connection list --format json | ConvertFrom-Json
    $connection = $connections | Where-Object id -eq $profile.connectionRef
    if (-not $connection -or $connection.environmentUrl.TrimEnd('/') -ne $url.TrimEnd('/')) {
        throw "Profile '$name' does not target the recorded $Target URL. Repair the profile with CP04 before continuing."
    }
    if ($profile.credentialRef -ne (Get-LabValue 'txcAuth')) {
        throw "Profile '$name' uses a different credential from CP01. Reconcile the tenant/auth selection first."
    }
    $other = if ($Target -eq 'dev') { 'test' } else { 'dev' }
    if ((Get-LabValue "${other}EnvUrl") -and (Get-LabValue "${other}EnvUrl").TrimEnd('/') -eq $url.TrimEnd('/')) {
        throw 'Dev and Test must be separate environments.'
    }
    # Never infer a target from whichever profile happens to be active.
}
# ── Template expansion ──────────────────────────────────────────────────────────────────
function Get-LabConnectorConnection {
    param([Parameter(Mandatory)][ValidateSet('dev', 'test')][string]$Target)
    Assert-LabProfile $Target
    $environmentId = Get-LabValue "${Target}EnvId"
    if (-not $environmentId) { throw "Run CP04 to resolve the $Target environment ID before binding a connector." }
    $response = Invoke-LabNative pa connector list --environment-id $environmentId --search 'Open Food Facts' --json --non-interactive | ConvertFrom-Json
    if (-not $response.success) { throw 'Connector discovery failed. Run pa auth login in the same tenant as txc.' }
    $connectors = @($response.items | Where-Object displayName -eq 'Open Food Facts')
    if ($connectors.Count -ne 1 -or -not $connectors[0].name) {
        throw "Expected exactly one deployed Open Food Facts connector in $Target; found $($connectors.Count)."
    }

    $connectorId = $connectors[0].name
    $response = Invoke-LabNative pa connection list --environment-id $environmentId --json --non-interactive | ConvertFrom-Json
    if (-not $response.success) { throw "Connection discovery failed in $Target." }
    $connections = @($response.items | Where-Object { ($_.properties.apiId -split '/')[-1] -eq $connectorId })
    if ($connections.Count -gt 1) { throw "Multiple Open Food Facts connections exist in $Target. Keep one intended lab connection before continuing." }
    $connectionId = if ($connections.Count) { $connections[0].name } else { $null }
    if (-not $connectionId) {
        Write-Info "Creating the $Target connection may require browser consent. This is separate from txc authentication."
        $arguments = @('connection', 'create', '--environment-id', $environmentId, '--connector', $connectorId, '--display-name', 'Open Food Facts', '--json')
        if ($env:LAB_AUTO -eq '1') { $arguments += '--non-interactive' }
        $created = Invoke-LabNative pa $arguments | ConvertFrom-Json
        if (-not $created.success -or -not $created.connectionId) { throw "Connection creation did not return an ID for $Target." }
        $connectionId = $created.connectionId
    }
    return @{ EnvironmentId = $environmentId; ConnectorId = $connectorId; ConnectionId = $connectionId }
}

function Get-LabCheckpoints {
    @(
        @{ Id='cp01'; Keys=@('txcAuth','tenantId','randomIdentifier'); Files=@() }
        @{ Id='cp02'; Keys=@('slnxName','publisherName','publisherPrefix'); Files=@('WarehouseManagement.slnx') }
        @{ Id='cp03'; Keys=@('repo','mainRulesetId'); Files=@() }
        @{ Id='cp04'; Keys=@('devEnvUrl','testEnvUrl','devProfile','testProfile'); Files=@() }
        @{ Id='cp05'; Keys=@('appId'); Files=@('.github/workflows/build.yml','.github/workflows/deploy.yml') }
        @{ Id='cp06'; Keys=@(); Files=@('src/Packages.Main/Packages.Main.csproj','src/Solutions.DataModel/Solutions.DataModel.csproj') }
        @{ Id='cp07'; Keys=@(); Files=@('src/Plugins.Warehouse/WarehouseStock.cs','src/Solutions.Logic/Solutions.Logic.csproj') }
        @{ Id='cp08'; Keys=@(); Files=@('src/Solutions.Security/Solutions.Security.csproj') }
        @{ Id='cp09'; Keys=@(); Files=@('src/Solutions.UI/Solutions.UI.csproj','src/Apps.WarehousePicking/package.json') }
        @{ Id='cp10'; Keys=@(); Files=@('src/Solutions.Security/Solutions.Security.csproj') }
        @{ Id='cp11'; Keys=@(); Files=@('src/Connectors.OpenFoodFacts/Connectors.OpenFoodFacts.csproj','src/Apps.WarehousePicking/src/components/BarcodeScanDialog.tsx'); Tags=@('cp11-data','cp11-connector','cp11-binding','cp11-ui') }
        @{ Id='cp12'; Keys=@('configDataDirectory','configDataSchemaPath','configDataFilePath'); Files=@('src/Packages.Main/Data/data.xml') }
        @{ Id='cp13'; Keys=@('mainRulesetId'); Files=@('.github/workflows/build.yml') }
        @{ Id='cp14'; Keys=@(); Files=@('src/Tests.UI/Tests.UI.csproj') }
        @{ Id='cp15'; Keys=@(); Files=@('src/Tests.Plugins/Tests.Plugins.csproj','src/Tests.Scripts/Tests.Scripts.csproj') }
        @{ Id='cp16'; Keys=@(); Files=@('.github/agents/bdd-warehouse-planner.agent.md'); Optional=$true }
        @{ Id='cp17'; Keys=@(); Files=@('.github/agents/bdd-warehouse-explorer.agent.md'); Optional=$true }
    )
}

function Test-LabCheckpointRecorded {
    param([string]$Id)
    if (-not (Get-LabValue "checkpoint:$Id")) { return $false }
    return [bool](Invoke-LabNative git -C $LabRoot tag --merged HEAD --list $Id "$Id-*")
}

function Invoke-LabStage {
    param([string]$Id, [scriptblock]$Action)
    if (Test-LabCheckpointRecorded $Id) { Write-Info "$Id is already recorded; continuing to the next stage."; return }
    & $Action
}

function Wait-LabTestDeployment {
    if ($env:LAB_LOCAL_MODE -eq '1') { return }
    $repo = Get-LabRepository
    $commit = Invoke-LabNative git -C $LabRoot rev-parse HEAD
    Write-Info "Waiting for the Test deployment of $commit..."
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        $runs = @(Invoke-LabNative gh run list -R $repo --workflow deploy.yml --commit $commit --limit 10 --json databaseId,status,conclusion | ConvertFrom-Json)
        if ($runs.Count) {
            $run = $runs[0]
            Invoke-LabNative gh run watch $run.databaseId -R $repo --exit-status
            $finished = Invoke-LabNative gh run view $run.databaseId -R $repo --json conclusion | ConvertFrom-Json
            if ($finished.conclusion -ne 'success') { throw 'Test deployment did not succeed. Inspect Actions before importing data.' }
            return
        }
        Start-Sleep 5
    }
    throw 'Test deployment did not start. Inspect the main-branch build and Actions permissions before continuing.'
}

# Renders a whole-file template from .lab-scripts/templates/ by replacing __TOKEN__
# placeholders with literal values (plain string replace, no regex — so scaffold scripts
# no longer need backtick-escaping for target languages that use $ themselves, like C#
# interpolated strings or JS/TS template literals).
function Expand-LabTemplate {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Destination,
        [hashtable]$Tokens = @{}
    )
    $content = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "../templates/$Path")
    foreach ($key in $Tokens.Keys) {
        $content = $content.Replace("__${key}__", [string]$Tokens[$key])
    }
    $destDir = Split-Path $Destination -Parent
    if ($destDir -and -not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    Set-Content -LiteralPath $Destination -Value ($content.TrimEnd() + "`n") -Encoding UTF8 -NoNewline
}

# ── Checkpoint via Pull Request ─────────────────────────────────────────────────────────
# Proper ALM: every checkpoint lands on main through a PR. We branch, commit, push, open a
# PR, pause so you can review the diff + checks in the browser, then merge + tag for rollback.
# Set LAB_AUTO_MERGE=1 to skip the pause (used for unattended testing).
# Set LAB_LOCAL_MODE=1 to skip GitHub entirely — commits merge into main locally, no push/PR.
function Save-Checkpoint {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Message,
        [string]$Body
    )
    Push-Location $LabRoot
    try {
        $email = git config user.email
        if (-not $email) {
            if ($env:LAB_LOCAL_MODE) {
                Invoke-LabNative git @('config', 'user.email', 'agent@local.test')
                Invoke-LabNative git @('config', 'user.name', 'alm-lab-agent')
            } else {
                $user = Invoke-LabNative gh @('api', 'user') | ConvertFrom-Json
                Invoke-LabNative git @('config', 'user.email', "$($user.id)+$($user.login)@users.noreply.github.com")
                Invoke-LabNative git @('config', 'user.name', $user.login)
            }
        }
        $branch = Invoke-LabNative git @('branch', '--show-current')
        if ($branch -ne 'main' -and $branch -notlike "$Id-*") {
            throw "Finish or switch away from branch '$branch' before saving $Id. Your changes have been left intact."
        }
        $Global:Lab["checkpoint:$Id"] = $true
        Save-LabState
        $changes = Invoke-LabNative git @('status', '--porcelain')
        $ahead = Invoke-LabNative git rev-list --count main..HEAD
        if (-not $changes -and [int]$ahead -eq 0) {
            Invoke-LabNative git switch main --quiet
            Write-Info "No source changes for $Id. Existing completion evidence is unchanged."
            return
        }
        if ($branch -eq 'main') {
            $branch = "$Id-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
            Invoke-LabNative git @('switch', '-c', $branch, '--quiet')
        }
        if ($changes) {
            Invoke-LabNative git @('add', '--all')
            Invoke-LabNative git @('commit', '-m', "$Id`: $Message", '-m', 'Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>')
        }
        if ($env:LAB_LOCAL_MODE -eq '1') {
            Invoke-LabNative git @('switch', 'main', '--quiet')
            Invoke-LabNative git @('merge', '--no-ff', '--quiet', '-m', "Merge $Id`: $Message`n`nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>", $branch)
        } else {
            $forkRepo = Get-LabRepository
            Invoke-LabNative git @('push', '-u', 'origin', $branch)
            $prs = @(Invoke-LabNative gh @('pr', 'list', '-R', $forkRepo, '--head', $branch, '--state', 'open', '--json', 'number,url') | ConvertFrom-Json)
            if ($prs.Count -eq 0) {
                $prBody = if ([string]::IsNullOrWhiteSpace($Body)) { $Message } else { $Body }
                Invoke-LabNative gh @('pr', 'create', '-R', $forkRepo, '--base', 'main', '--head', $branch, '--title', "$Id`: $Message", '--body', $prBody)
            } else { Write-Info "Resuming $($prs[0].url)" }
            if ($env:LAB_AUTO_MERGE -ne '1') { Read-Host 'Review the PR, then press Enter to wait for checks and merge' | Out-Null }
            if (Test-Path '.github/workflows/build.yml') {
                $checks = @()
                for ($i = 0; $i -lt 30; $i++) {
                    $pr = Invoke-LabNative gh @('pr', 'view', $branch, '-R', $forkRepo, '--json', 'statusCheckRollup') | ConvertFrom-Json
                    $checks = @($pr.statusCheckRollup)
                    if ($checks.Count -gt 0) { break }
                    Start-Sleep 5
                }
                if ($checks.Count -eq 0) { throw "Checks did not start. Enable Actions on your fork, then resume this PR." }
                Invoke-LabNative gh @('pr', 'checks', $branch, '-R', $forkRepo, '--watch')
            }
            Invoke-LabNative gh @('pr', 'merge', $branch, '-R', $forkRepo, '--squash', '--delete-branch')
            Invoke-LabNative git @('switch', 'main', '--quiet')
            Invoke-LabNative git @('pull', '--ff-only', '--quiet')
        }
        $tag = $Id
        if (Invoke-LabNative git @('tag', '--list', $tag)) { $tag = "$Id-$([guid]::NewGuid().ToString('N').Substring(0, 8))" }
        Invoke-LabNative git @('tag', $tag)
        if ($env:LAB_LOCAL_MODE -ne '1') { Invoke-LabNative git @('push', 'origin', "refs/tags/${tag}:refs/tags/${tag}") }
        Write-Ok "Merged + tagged $tag. Deployment and live acceptance are separate checks."
    } finally { Pop-Location }
}

Import-LabState | Out-Null

# Checkpoints own a clean worktree. Resume an interrupted run by inspecting/committing its
# changes on the checkpoint branch first; never silently include unrelated work.
$caller = [System.IO.Path]::GetFileName($MyInvocation.ScriptName)
if ($caller -match '^CP\d{2}.*\.ps1$') {
    $dirty = Invoke-LabNative git @('-C', $LabRoot, 'status', '--porcelain')
    if ($dirty) { throw "The worktree is not clean. Commit or stash your changes before $caller; nothing has been staged." }
    if ($env:LAB_LOCAL_MODE -eq '1' -and $env:LAB_DISPOSABLE -ne '1') {
        throw "Local mode must run in a disposable checkout. Use the local rehearsal runner, not your working repository."
    }
    if ($env:LAB_LOCAL_MODE -ne '1' -and (Get-LabValue 'localMode')) {
        throw 'This state belongs to a local rehearsal. Start a fresh fork for the live lab.'
    }
    if ($env:LAB_LOCAL_MODE -ne '1') {
        $repo = Get-LabRepository
        if ((Get-LabValue 'repo') -and (Get-LabValue 'repo') -ne $repo) {
            throw "Lab state belongs to another fork. Do not reuse an attendee's completed state in $repo."
        }
    }
    if ($env:LAB_LOCAL_MODE -eq '1') { Set-LabValue 'localMode' $true }
    $number = [int]$caller.Substring(2, 2)
    if ($number -gt 1 -and $number -le 15) {
        $previous = @(Get-LabCheckpoints)[$number - 2]
        foreach ($file in $previous.Files) {
            if (-not (Test-Path (Join-Path $LabRoot $file))) { throw "Run $($previous.Id) first: missing $file." }
        }
        if ($env:LAB_LOCAL_MODE -ne '1') {
            foreach ($key in $previous.Keys) {
                if (-not (Get-LabValue $key)) { throw "Run $($previous.Id) first: missing state '$key'." }
            }
        }
    }
    $id = "cp$('{0:d2}' -f $number)"
    if ($id -eq 'cp11') {
        $id = @('cp11-data','cp11-connector','cp11-binding','cp11-ui') | Where-Object { -not (Test-LabCheckpointRecorded $_) } | Select-Object -First 1
        if (-not $id) { $id = 'cp11-data' }
    }
    $branch = Invoke-LabNative git -C $LabRoot branch --show-current
    if ($branch -eq 'main') {
        if ($env:LAB_LOCAL_MODE -ne '1') {
            Invoke-LabNative git -C $LabRoot pull --ff-only --quiet
            Import-LabState | Out-Null
        }
        Invoke-LabNative git -C $LabRoot switch -c "$id-$([guid]::NewGuid().ToString('N').Substring(0, 8))" --quiet
    } elseif ($branch -notlike "$id-*") {
        throw "Finish the existing checkpoint branch '$branch' before starting $caller."
    }
}
