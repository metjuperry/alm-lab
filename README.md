# Power Platform Developer ALM Lab
Power Platform with source-first ALM: a monorepo, ephemeral Dev/Test environments,
trunk-based development, PR quality gates and GitHub Actions deployments.

**This fork is a worked example, not a clean starter.** Its `src/`, checkpoint tags
and `.lab-state.json` came from a previous run. The original starter is
[TALXIS/alm-lab](https://github.com/TALXIS/alm-lab). Changes to this lab must be made
in `.lab-scripts/` and its templates as well as the generated example.

The scripts and templates are the maintained lab inputs; `src/` is their generated
result. The local rehearsal starts from the upstream starter, never from this
fork's generated app or cached state.

The lab pins its toolchain in `.lab-scripts/toolchain.json`. Its packaging
compatibility layer handles the known DevKit 1.9.0 validation issues by checking
actual archive contents and validating freshly staged metadata. Missing components
remain build failures; warnings are not blindly suppressed.

## Prerequisites and outcome

Use a GitHub account that can administer its fork and enable Actions, and a training
tenant with capacity and permission to create **two Dataverse Sandbox environments**.
You need permission to create Entra application registrations/service principals
and assign a deployment application user. App users need the appropriate Power Apps
licenses, a platform base role (for example Basic User), and the lab's worker or
manager role. Share the code app and its connector connection with those users.
Do not substitute a personal production environment for a sandbox.

CP01 checks .NET, Git, gh, pac, txc, az, Node (22.12+) and **pa**. The pa login used
for code-app connection binding is separate from txc/az; it must use the same
training tenant. CP11 may require browser consent when creating a connection.
Tool/template upgrades are explicit, not performed silently on every restart.
The devcontainer installs the pinned CLI/templates once at creation. On another
machine, `.lab-scripts/Install-LabToolchain.ps1` installs those versions explicitly
and changes that user's global tools/template registry. CP02 restores its pinned
PAC tool locally, without replacing another project's PAC installation.

The core app manages a grocery warehouse: locations, items, stock movements and
barcode-sourced Products. Managers use the model-driven app; workers use Warehouse
Picking. Movements must be positive; creating, editing or deleting them adjusts
stock atomically or is rejected. New items start at zero. Managers can correct or
delete any movement; workers can edit their own but cannot delete.

## Start here

1. **Fork the starter**, not a completed attendee run, to your personal GitHub account.
   For recipe development in this fork, use the isolated [local rehearsal](LOCAL-DRY-RUN.md).
2. On **your fork** (`https://github.com/<you>/alm-lab`), click **Code → Codespaces → Create codespace on main**.
   All tools are preinstalled. The Codespace and free GitHub Actions minutes run on *your* account.

   > ⚠️ Don't use a "one-click" badge that points at `TALXIS/alm-lab` — that starts the Codespace on the parent repo, where you can't push and your free minutes won't apply. Always launch from your own fork.

3. Wait for VS Code to load in the browser. Open a terminal (Ctrl+`) — you're in PowerShell.
4. Run **CP01–CP15 in order**, starting from a clean worktree. Do not infer completion
   from generated files alone. `.lab-scripts/lab-status.ps1` checks checkpoint tags on
   the current history, expected files/state, and local CLI sessions. A source
   checkpoint is not evidence that Test deployed successfully.

> 💡 Each checkpoint script is fully commented — open it, read what it does, then run it.
> Run whole checkpoint scripts so their preflight and error handling are not skipped.

### Signing in (CP01)

`CP01` signs you in to everything up front: **GitHub** (`gh`), **Power Platform** (`txc`) and
**Azure** (`az`). Two of these use a **device code** — the terminal prints a code and a URL;
open it, paste the code, and approve. When prompted, allow the `workflow` scope for `gh` so
later checkpoints can install GitHub Actions on your fork.

## How each checkpoint works (PR flow)

Checkpoints don't push straight to `main` — they teach the real ALM loop. Each one:

1. Creates a branch and commits its changes.
2. Opens a **Pull Request** and prints the link.
3. **Pauses** — open the PR in your browser, review the diff and the running build check.
4. Press **Enter** to continue: it waits for checks, merges without admin bypass, and
   records an immutable tag. Early layout checkpoints have no build workflow yet.

Failures stop rather than advance the checkpoint. Your branch and changes remain
available for inspection; finish or repair that PR before starting another
checkpoint. Test deployment runs asynchronously after the build; CP12 waits for
the deployment of its current commit before importing data. Inspect **Actions →
deploy** if it fails, and wait for deployment before dispatching live tests.
CP11 records four separate stage tags so a table-only run is not mistaken
for completed integration.

This is the slow, deliberate part — read the PR, watch the build go green, then merge. The
first time a checkpoint enables GitHub Actions you may be asked to **approve workflows on your
fork** — say yes.

## Checkpoints

| # | Script | Goal |
|---|--------|------|
| 01 | `CP01-check-machine-setup.ps1` | Verify all tools are installed |
| 02 | `CP02-create-repository-layout.ps1` | Monorepo layout (solution, src, NuGet) |
| 03 | `CP03-setup-continuous-integration.ps1` | Branch protection — gated PRs into main |
| 04 | `CP04-setup-runtime.ps1` | Create Dev + Test Dataverse environments |
| 05 | `CP05-setup-continuous-deployment.ps1` | OIDC service principal + deploy workflow |
| 06 | `CP06-implement-data-model.ps1` | Warehouse tables and columns |
| 07 | `CP07-implement-backend.ps1` | Plugins + logic solution |
| 08 | `CP08-implement-security.ps1` | Security roles |
| 09 | `CP09-implement-ui.ps1` | Model-driven app, sitemap, forms, views, grid PCF, warehouse picking code app |
| 10 | `CP10-deploy-and-sync.ps1` | Deploy **unmanaged Debug** to Dev & pull changes back; CD deploys **managed Release** to Test |
| 11 | `CP11-integrate-external-data.ps1` | Product table, connector, environment-specific binding, barcode UI, updated Dev deployment |
| 12 | `CP12-move-configuration.ps1` | Configuration data migration (CMT) |
| 13 | `CP13-extend-branch-policies-build-checks.ps1` | Require build check on PRs |
| 14 | `CP14-automate-ui-testing.ps1` | BDD UI project + manual live workflow; configure test accounts and the deployed app URL |
| 15 | `CP15-implement-unit-tests.ps1` | Plugin (FakeXrmEasy) + script (Jest) unit tests |
| Optional 16 | `CP16-plan-tests-with-agent.ps1` | Install the planning agent; invoke it separately and review its proposed scenarios |
| Optional 17 | `CP17-explore-blackbox-and-generate-tests.ps1` | Install the black-box explorer; invoke it separately and review its findings |

Terraform CP04b/CP05b is an [optional alternative](infra/README.md) to CP04/CP05,
never an additional pair to run in sequence. The generative dashboard is also
optional: its page needs a verified separate upload before navigation is enabled.
The core app does not depend on it.

Run a checkpoint:

```powershell
.lab-scripts/CP01-check-machine-setup.ps1
```

## Rollback

Tags identify source milestones, not environment snapshots. Inspect one without
overwriting your current work:

```powershell
git switch -c inspect-cp05 cp05
```

To undo a merged change, use a reviewed revert PR. Do not force-push protected
`main`. Reverting source does not reverse data writes, uninstall managed solutions,
or restore Terraform state. Never automatically uninstall a managed Dev solution
to make a pull work: use a fresh sandbox or an explicitly reviewed migration.

## Resuming on a different machine

`.lab-state.json` travels with the repo, but auth sessions and CLI profiles (gh/txc/az)
live on whatever machine you're on right now — they don't come along with a `git clone`.
To pick up the lab on a fresh Codespace, VM, or after a crash:

1. Clone the repo (or open a new Codespace on your fork).
2. If you want to resume from a specific checkpoint rather than the latest commit:
   `git switch -c inspect-cp07 cp07` to inspect it; return to `main` before continuing.
3. Run `.lab-scripts/lab-status.ps1` — it reports which checkpoints are done according to
   `.lab-state.json` and git tags, and whether this machine's own `gh`/`txc`/`az` sessions
   actually match what lab-state expects (a mismatch here is the most common reason a
   checkpoint fails partway through instead of at the top with a clear message).
4. Re-run CP01 if `lab-status.ps1` flags missing/mismatched auth, then continue with
   whichever checkpoint it names as next.

## Running the tests in VS Code

`.vscode/extensions.json` recommends the extensions that put the three suites in the Testing
panel: C# Dev Kit for the plugin and UI tests, and the Jest extension for `src/Tests.Scripts`
(those tests are Jest, not .NET, so the .NET provider will never find them).

The Gherkin scenarios appear as ordinary .NET tests — Reqnroll generates one `[TestMethod]` per
scenario into a `*.feature.cs` at build time, so **build once before expecting scenarios to show
up**, and rebuild after editing a `.feature` file.

> ⚠️ **macOS: C# Dev Kit cannot use Homebrew's .NET.** If `dotnet` came from `brew`, the Testing
> panel stays empty and Dev Kit claims "a supported .NET 10 SDK is not installed" however new your
> SDK is. Two separate problems hide behind that one message, and only the second is fatal:
>
> 1. `/opt/homebrew/bin/dotnet` is a wrapper script that sets `DOTNET_ROOT` and execs the real host
>    under `libexec/`. Dev Kit inspects paths rather than running it, looks for an `sdk/` next to
>    `bin/dotnet`, finds none, and refuses to select the host.
> 2. Get past that and the server fails to load Homebrew's `libhostfxr.dylib` outright:
>
>    ```
>    code signature ... not valid for use in process:
>    mapping process and mapped file (non-platform) have different Team IDs
>    ```
>
>    Dev Kit's server runs with hardened runtime and library validation, so macOS will only map
>    libraries signed by the same Team ID. Homebrew's .NET is **ad-hoc signed**
>    (`TeamIdentifier=not set`); Microsoft's is signed `UBF8T346G9`. Check an install with
>    `codesign -dvvv <dotnet-root>/host/fxr/*/libhostfxr.dylib`. No configuration fixes this.
>
> Install a Microsoft-signed SDK without admin rights, point Dev Kit at it in your **user**
> `settings.json` (not this repo's — the path is machine-specific), and **fully restart VS Code**;
> a window reload is not enough, because the extension host reads this once at launch:
>
> ```bash
> curl -fsSL https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh
> ./dotnet-install.sh --channel 10.0 --install-dir "$HOME/.dotnet" --no-path
> ```
>
> ```jsonc
> "dotnetAcquisitionExtension.existingDotnetPath": [
>   { "extensionId": "ms-dotnettools.csdevkit", "path": "/Users/<you>/.dotnet/dotnet" },
>   { "extensionId": "ms-dotnettools.csharp",   "path": "/Users/<you>/.dotnet/dotnet" }
> ]
> ```
>
> `/usr/local/share/dotnet` (the official `.pkg` location) is signed correctly too, but Dev Kit's
> floor is SDK **10.0.400** — an older official install there is refused with the same misleading
> message. Homebrew's `dotnet` can stay the one on your `PATH`; this setting only governs the host
> the extensions themselves run on.
>
> Throughout all of it `dotnet test` from a terminal works — the suites are fine, only Dev Kit's
> discovery is affected.

Browser scenarios additionally need a signed-in Playwright storage state; see
[src/Tests.UI/README.md](src/Tests.UI/README.md).

## Final walkthrough

Do not declare completion until **both Dev and Test** pass the deployed workflow:

1. Assign the lab roles and app/connection access to distinct non-admin test users.
2. As manager, open Locations, Items, Transactions and Products; create an item
   with zero initial stock and an inbound movement.
3. As worker, make a valid pick and confirm the stored quantity changes. Over-pick:
   an error must remain visible, the form stays open, and no movement is stored.
4. Edit your own movement; as manager, edit/delete it. Confirm the old effect is
   reversed and the new one applied. A correction that would make stock negative
   must leave both records and quantities unchanged.
5. Scan or type `3017620422003` on a grocery item, link the result, then reopen it
   and confirm the Product link persisted. Check Test with its own connection,
   not a connection copied from Dev.
6. Pull a deliberate unmanaged Dev change into source, review it in a PR, and
   confirm the corresponding managed Test deployment succeeds.

CP11 provisions environment-specific connector connections and records the Test
connection IDs in repository variables. The deployed code app uses a logical
Dataverse connection reference, not a copied Dev connection. CD binds that
reference after import; CP12 discovers the actual Test app URL and sets
`TXC_CODEAPP_URL`.

The live test workflow still needs the dedicated account secrets listed in the
test README. A green build, installed agent definition, or skipped
browser suite is not a substitute for this walkthrough.

## Developing this lab

See [LOCAL-DRY-RUN.md](LOCAL-DRY-RUN.md) to run the checkpoints locally, without forking to
GitHub or provisioning real infrastructure.
