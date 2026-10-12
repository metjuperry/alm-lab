# Local source rehearsal

Run from a fresh **isolated** Git repository, not the completed working checkout:

```powershell
.lab-scripts/Test-LabLocal.ps1
```

The runner extracts upstream commit `ca8221504a9628375a690b275633dad1c8ec5a07`,
overlays the candidate checkpoint recipes, initializes separate local Git history
and runs only CP01–CP15. It never copies generated `src/`, personal lab state, tags
or build caches from this checkout. `-Through 5` runs only the setup portion;
`-Destination <new-directory>` selects a destination that must not already exist.
The checkout is retained at the printed path, including on failure.

Tools must already be installed. Alternatively, with Docker running:

```bash
docker run -it --rm \
  -v "$PWD":/source:ro -w /source \
  ghcr.io/talxis/tools-agentbox/image:latest \
  pwsh -NoProfile -File .lab-scripts/Test-LabLocal.ps1
```

The source mount is read-only; generated files and checkpoint commits belong to the
container's disposable filesystem. Copy out any wanted artifacts before exiting.
Do not bind-mount your working checkout read/write and run a wildcard over `CP*`:
that includes mutually exclusive imperative/Terraform paths and changes your Git
history.

The runner sets `LAB_LOCAL_MODE=1`, `LAB_DISPOSABLE=1`, `LAB_AUTO=1` and
`LAB_AUTO_MERGE=1` only for its execution. Cloud operations are skipped; generation,
package downloads and builds still run. This is **not** an offline/network-free
test, and it does not prove authentication, deployment, connection binding, or the
hosted app works. Never use its placeholder state for a live run.

## Fast checks

```powershell
pwsh -NoProfile -File .lab-scripts/tests/Lab.Common.Tests.ps1
pwsh -NoProfile -File .lab-scripts/tests/PackSolution.Tests.ps1
pwsh -NoProfile -File .lab-scripts/tests/ConnectionReference.Tests.ps1
pwsh -NoProfile -File .lab-scripts/tests/Checkpoint.Failures.Tests.ps1
pwsh -NoProfile -File .lab-scripts/tests/Parity.Tests.ps1
node --experimental-strip-types --test .lab-scripts/tests/operation-result.test.mjs
dotnet test src/Tests.Plugins/Tests.Plugins.csproj
npm test --prefix src/Tests.Scripts -- --ci
dotnet test src/Tests.UI/Tests.UI.csproj --filter "TestCategory!=live"
```

Build `Scripts.UI` before its Jest tests. These checks do not require a Dataverse
environment.

- `Checkpoint.Failures.Tests.ps1` injects failures in a throwaway Git repository with
  stubbed `gh`/`txc`: mismatched profiles, a failing commit, a failing required check,
  checks that never start, a failed Test deployment, unmerged tags and no-change
  reruns. None of them may produce a tag or completion, and the checkpoint branch and
  existing PR are kept so the run can resume.
- `Parity.Tests.ps1` compares what the recipes generate with the completed example:
  plugin, test and code-app templates, installed workflows, plugin step registrations
  and pre-images, sitemap/app-module Product navigation, role privileges, and leftover
  template tokens. Run it after changing a template or regenerating a file.

## Packaging compatibility

The pinned templates generate DevKit 1.9.0 projects. `Directory.Build.targets`
imports the lab's narrowly scoped packaging compatibility:

- Stage current solution content before validation, avoiding the stale-output
  problem tracked in TALXIS/tools-devkit-build#122.
- Pack with the locally pinned PAC tool and verify that reported SystemForm and
  connector components really exist in the resulting archive. This handles
  TALXIS/tools-devkit-build#118 without accepting genuinely missing components.
- Reject incomplete packages and remove failed output archives.

The draft flow under `src/Solutions.Logic/Workflows/` is not part of the lab. The
`LabExcludeWorkflows` target removes it, and its solution root component, from the
staged copy at pack time only; the sources stay untouched. Pass
`-p:LabIncludeWorkflows=true` to pack it once its files are named with the real
publisher prefix.

CP15 publishes and inspects the final managed deployment package: all five
solutions, correct import order, stock registrations/pre-images, both app surfaces,
the connector/reference and grocery data must be present. The same check runs in CI.

Corporate TLS interception must be handled by trusting the organization's CA in
the container/host. Do not disable certificate verification to get restores to pass.

## Optional black-box explorer

Run only against an authorized disposable environment after the app is deployed.
`playwright-cli` sessions are working-directory scoped. Establish a signed-in
session from the repo root, then supply the agent definition as prompt text rather
than asking the source-blind agent to read it:

```bash
playwright-cli -s=explorer open
playwright-cli -s=explorer state-load "$PWD/src/Tests.UI/.auth/state-<account>.json"
playwright-cli -s=explorer goto "https://apps.powerapps.com/play/e/<env-id>/a/<app-id>"
playwright-cli -s=explorer snapshot
```

The snapshot must show the app, not sign-in. Give the agent the full text of
`.github/agents/bdd-warehouse-explorer.agent.md`, tell it to reuse `explorer`, and
specify the allowed environment/data. Review its output before promoting scenarios
from `Features/Discovered/` into the executable suite.

## What is and is not proven

Proven locally: clean-starter CP01–CP05 generation and rerun, source builds of all
projects, the unit/offline suites above, checkpoint failure handling, and
recipe/example parity.

Not proven until a dedicated live run: CP06 on a fresh starter with the pinned
packager, Test-side connection binding with a real connection, OIDC deployment,
Dataverse rollback and concurrency for stock movements, non-admin persona access,
and the hosted barcode flow. Dev and Test profiles must point at two separate
sandbox environments first; the live path has not been rehearsed.
