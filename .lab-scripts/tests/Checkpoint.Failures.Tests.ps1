$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../lib/Lab.Common.ps1"

function Assert-Equal($Expected, $Actual, $What = 'value') {
    if ($Expected -ne $Actual) { throw "$What`: expected '$Expected'; got '$Actual'." }
}
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    try { & $Action } catch {
        if ($_.Exception.Message -notlike "*$Message*") { throw "Wrong failure. Expected '*$Message*'; got: $($_.Exception.Message)" }
        return
    }
    throw "Expected failure containing '$Message'."
}
function Invoke-TestGit { & git -C $script:Repo @args; if ($LASTEXITCODE -ne 0) { throw "git $args failed" } }

$saved = @{ Root = $Global:LabRoot; State = $Global:LabStateFile; Lab = $Global:Lab }
$envSaved = @{}
foreach ($key in 'LAB_LOCAL_MODE', 'LAB_AUTO_MERGE', 'LAB_DISPOSABLE') { $envSaved[$key] = [Environment]::GetEnvironmentVariable($key) }
$script:Repo = Join-Path ([IO.Path]::GetTempPath()) "lab-failure-tests-$([guid]::NewGuid().ToString('N'))"
$bare = "$script:Repo-remote"
try {
    # ── Assert-LabProfile: mismatched or inherited targets stop before any mutation ──
    $env:LAB_LOCAL_MODE = $null
    $script:profiles = @(@{ id = 'dev-p'; connectionRef = 'c-dev'; credentialRef = 'auth1' })
    $script:connections = @(@{ id = 'c-dev'; environmentUrl = 'https://dev.crm.example/' })
    function txc {
        $global:LASTEXITCODE = 0
        if ($args -contains 'profile') { ConvertTo-Json -InputObject @($script:profiles) -Depth 5 }
        else { ConvertTo-Json -InputObject @($script:connections) -Depth 5 }
    }
    $Global:Lab = @{ devProfile = 'dev-p'; devEnvUrl = 'https://dev.crm.example'; txcAuth = 'auth1'; testEnvUrl = 'https://test.crm.example' }
    Assert-LabProfile dev   # healthy baseline passes
    $Global:Lab.devEnvUrl = 'https://x.stub.invalid'
    Assert-Throws { Assert-LabProfile dev } 'dry run'
    $Global:Lab.devEnvUrl = 'https://dev.crm.example'
    $Global:Lab.devProfile = 'ghost'
    Assert-Throws { Assert-LabProfile dev } 'missing on this machine'
    $Global:Lab.devProfile = 'dev-p'
    $script:connections = @(@{ id = 'c-dev'; environmentUrl = 'https://someone-else.crm.example' })
    Assert-Throws { Assert-LabProfile dev } 'does not target the recorded'
    $script:connections = @(@{ id = 'c-dev'; environmentUrl = 'https://dev.crm.example' })
    $Global:Lab.txcAuth = 'other-auth'
    Assert-Throws { Assert-LabProfile dev } 'different credential'
    $Global:Lab.txcAuth = 'auth1'
    $Global:Lab.testEnvUrl = 'https://dev.crm.example/'
    Assert-Throws { Assert-LabProfile dev } 'separate environments'
    Remove-Item function:txc

    # ── Disposable repository standing in for the learner's fork ──
    git init -q --bare -b main $bare
    git init -q -b main $script:Repo
    Invoke-TestGit config user.email lab@local.invalid
    Invoke-TestGit config user.name lab
    Invoke-TestGit commit -q --allow-empty -m init
    Invoke-TestGit remote add origin https://github.com/learner/alm-lab.git
    Invoke-TestGit config remote.origin.pushurl $bare
    $Global:LabRoot = $script:Repo
    $Global:LabStateFile = Join-Path $script:Repo '.lab-state.json'
    $Global:Lab = @{}

    # ── Local mode: merge + tag; rerun without changes leaves evidence alone ──
    $env:LAB_LOCAL_MODE = '1'
    Set-Content (Join-Path $script:Repo 'a.txt') 'one'
    Save-Checkpoint -Id cp90 -Message 'first'
    Assert-Equal 1 @(git -C $script:Repo tag --list 'cp90*').Count 'tags after first run'
    Assert-Equal $true (Test-LabCheckpointRecorded 'cp90') 'recorded after merge'
    $head = git -C $script:Repo rev-parse HEAD
    Save-Checkpoint -Id cp90 -Message 'again'
    Assert-Equal $head (git -C $script:Repo rev-parse HEAD) 'HEAD after no-change rerun'
    Assert-Equal 1 @(git -C $script:Repo tag --list 'cp90*').Count 'tags after no-change rerun'

    # Rerun with new work must not move or delete the existing tag.
    $firstTag = git -C $script:Repo rev-parse cp90
    Set-Content (Join-Path $script:Repo 'b.txt') 'two'
    Save-Checkpoint -Id cp90 -Message 'more'
    Assert-Equal $firstTag (git -C $script:Repo rev-parse cp90) 'original tag target'
    Assert-Equal 2 @(git -C $script:Repo tag --list 'cp90*').Count 'tags after a rerun with work'

    # Ancestry: a tag outside HEAD, or missing state, is not completion evidence.
    Invoke-TestGit switch -q -c side
    Set-Content (Join-Path $script:Repo 'side.txt') 's'
    Invoke-TestGit add --all
    Invoke-TestGit commit -q -m side
    Invoke-TestGit tag cp91-sidetag
    Invoke-TestGit switch -q main
    $Global:Lab['checkpoint:cp91'] = $true
    Assert-Equal $false (Test-LabCheckpointRecorded 'cp91') 'unmerged tag'
    $Global:Lab.Remove('checkpoint:cp90')
    Assert-Equal $false (Test-LabCheckpointRecorded 'cp90') 'tag without recorded state'
    $Global:Lab['checkpoint:cp90'] = $true

    # Stage runner skips recorded work and runs unrecorded work.
    $script:ran = 0
    Invoke-LabStage 'cp90' { $script:ran++ }
    Invoke-LabStage 'cp92' { $script:ran++ }
    Assert-Equal 1 $script:ran 'stages executed'

    # A wrong branch stops without touching the learner's changes.
    Invoke-TestGit switch -q -c scratch
    Set-Content (Join-Path $script:Repo 'keep.txt') 'mine'
    Assert-Throws { Save-Checkpoint -Id cp93 -Message 'x' } 'Finish or switch away'
    Assert-Equal 'mine' ((Get-Content (Join-Path $script:Repo 'keep.txt') -Raw).Trim()) 'uncommitted work'
    Remove-Item (Join-Path $script:Repo 'keep.txt')
    Invoke-TestGit switch -q main

    # A failing commit hook never produces a tag or completion.
    $hook = Join-Path $script:Repo '.git/hooks/pre-commit'
    Set-Content $hook "#!/bin/sh`nexit 1`n"
    chmod +x $hook
    Set-Content (Join-Path $script:Repo 'c.txt') 'three'
    Assert-Throws { Save-Checkpoint -Id cp94 -Message 'blocked' } 'git failed'
    Assert-Equal 0 @(git -C $script:Repo tag --list 'cp94*').Count 'tags after failed commit'
    Assert-Equal $false (Test-LabCheckpointRecorded 'cp94') 'completion after failed commit'
    Remove-Item $hook
    Invoke-TestGit switch -q main --force 2>$null
    Invoke-TestGit reset -q --hard
    Invoke-TestGit clean -qfd -e .lab-state.json

    # ── Live mode with stubbed gh: a failed required check blocks the merge and the tag ──
    $env:LAB_LOCAL_MODE = $null
    $env:LAB_AUTO_MERGE = '1'
    New-Item -ItemType Directory (Join-Path $script:Repo '.github/workflows') -Force | Out-Null
    Set-Content (Join-Path $script:Repo '.github/workflows/build.yml') 'name: build'
    Invoke-TestGit add --all
    Invoke-TestGit commit -q -m 'add build workflow'
    $Global:Lab['localMode'] = $null
    $script:ghCalls = @()
    $script:checksExit = 1
    function gh {
        $script:ghCalls += ,($args -join ' ')
        $global:LASTEXITCODE = 0
        switch -Wildcard ($args -join ' ') {
            'pr list*'  { '[]' }
            'pr view*'  { '{"statusCheckRollup":[{"name":"build"}]}' }
            'pr checks*' { $global:LASTEXITCODE = $script:checksExit }
        }
    }
    Set-Content (Join-Path $script:Repo 'd.txt') 'four'
    Assert-Throws { Save-Checkpoint -Id cp95 -Message 'gated' } 'failed (exit 1)'
    if (@($script:ghCalls | Where-Object { $_ -like 'pr merge*' }).Count) { throw 'A failing check must not reach merge.' }
    Assert-Equal 0 @(git -C $script:Repo tag --list 'cp95*').Count 'tags after failed check'
    Assert-Equal $false (Test-LabCheckpointRecorded 'cp95') 'completion after failed check'
    $branch = git -C $script:Repo branch --show-current
    if ($branch -notlike 'cp95-*') { throw "The checkpoint branch must be kept for resuming; on '$branch'." }

    # Resuming reuses the open PR instead of creating a duplicate.
    $script:ghCalls = @()
    $script:checksExit = 1
    function gh {
        $script:ghCalls += ,($args -join ' ')
        $global:LASTEXITCODE = 0
        switch -Wildcard ($args -join ' ') {
            'pr list*'  { '[{"number":7,"url":"https://github.com/learner/alm-lab/pull/7"}]' }
            'pr view*'  { '{"statusCheckRollup":[{"name":"build"}]}' }
            'pr checks*' { $global:LASTEXITCODE = 1 }
        }
    }
    Assert-Throws { Save-Checkpoint -Id cp95 -Message 'gated' } 'failed (exit 1)'
    if (@($script:ghCalls | Where-Object { $_ -like 'pr create*' }).Count) { throw 'Resume must not open a second PR.' }

    # Checks that never start are reported, not merged past.
    $script:ghCalls = @()
    function gh {
        $script:ghCalls += ,($args -join ' ')
        $global:LASTEXITCODE = 0
        switch -Wildcard ($args -join ' ') {
            'pr list*' { '[{"number":7,"url":"u"}]' }
            'pr view*' { '{"statusCheckRollup":[]}' }
        }
    }
    function Start-Sleep { }
    Assert-Throws { Save-Checkpoint -Id cp95 -Message 'gated' } 'Checks did not start'
    Remove-Item function:Start-Sleep
    Invoke-TestGit switch -q main

    # ── Test deployment wait: failure must stop CP12 data import ──
    $env:LAB_LOCAL_MODE = $null
    $script:conclusion = 'failure'
    function gh {
        $global:LASTEXITCODE = 0
        switch -Wildcard ($args -join ' ') {
            'run list*' { '[{"databaseId":42,"status":"completed","conclusion":"failure"}]' }
            'run view*' { "{`"conclusion`":`"$script:conclusion`"}" }
        }
    }
    Assert-Throws { Wait-LabTestDeployment } 'did not succeed'
    $script:conclusion = 'success'
    Wait-LabTestDeployment
    function gh { $global:LASTEXITCODE = 0; if (($args -join ' ') -like 'run list*') { '[{"databaseId":42}]' } else { $global:LASTEXITCODE = 1 } }
    Assert-Throws { Wait-LabTestDeployment } 'failed (exit 1)'
    Remove-Item function:gh

    Write-Host 'Checkpoint failure-injection and resume tests passed.'
} finally {
    $Global:LabRoot = $saved.Root; $Global:LabStateFile = $saved.State; $Global:Lab = $saved.Lab
    foreach ($key in $envSaved.Keys) { [Environment]::SetEnvironmentVariable($key, $envSaved[$key]) }
    Remove-Item function:gh, function:txc, function:Start-Sleep -ErrorAction SilentlyContinue
    Remove-Item $script:Repo, $bare -Recurse -Force -ErrorAction SilentlyContinue
}
