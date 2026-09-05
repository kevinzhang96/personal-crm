# The self-hosted runner

`.github/workflows/deploy.yml` runs on the Mac Studio, because that is where
the signing certificate and the App Store Connect key are, and neither can
or should be copied into GitHub. Every push to `main` that touches code runs
the simulator tests and, if they pass, `ios/bin/release.sh` — a TestFlight
build, the same way a person would ship one.

This is the same arrangement as tcgdb's, and
[tcgdb's `deploy/CI_RUNNER_SETUP.md`](https://github.com/kevinzhang96/tcgdb/blob/main/deploy/CI_RUNNER_SETUP.md)
is the full treatment: what the runner needs, how to re-register one, how to
operate it, and the code-signing landmine below. This file records only what
is specific to Tend.

## What exists

GitHub runners are registered per repository, so Tend has its own instance
beside tcgdb's and order-tracker's — the same runner package, a separate
directory and registration:

| | |
|---|---|
| runner name | `studio-personal-crm`, labels `self-hosted`, `macOS`, `ARM64` |
| directory | `~/actions-runner-personal-crm` (package copied from `~/actions-runner`, which auto-updates; each instance updates itself too) |
| LaunchAgent | `~/Library/LaunchAgents/actions.runner.kevinzhang96-personal-crm.studio-personal-crm.plist` |
| logs | `~/Library/Logs/actions.runner.kevinzhang96-personal-crm.studio-personal-crm/` and `~/actions-runner-personal-crm/_diag/` |
| checkout it builds in | `~/actions-runner-personal-crm/_work/personal-crm/personal-crm` — never `~/code/personal-crm` |

Registered 2026-09-05 from this machine: `gh` holds the `repo` scope and
admin on the repository, which is enough to mint a registration token
(`gh api -X POST repos/kevinzhang96/personal-crm/actions/runners/registration-token`),
so no step needed the website.

## Code signing: `SessionCreate` must stay out of the plist

`svc.sh install` writes a LaunchAgent with `SessionCreate` true, which puts
the job in a security session of its own; `codesign` then cannot reach the
login keychain's private keys and fails with `errSecInternalComponent`. The
key is removed from Tend's installed plist. A re-install from a freshly
downloaded runner brings it back — check with

```sh
plutil -p ~/Library/LaunchAgents/actions.runner.kevinzhang96-personal-crm.studio-personal-crm.plist | grep -c SessionCreate
```

which must print `0`, and remove it again before `svc.sh start` if not:

```sh
plutil -remove SessionCreate ~/Library/LaunchAgents/actions.runner.kevinzhang96-personal-crm.studio-personal-crm.plist
```

The ordinary keychain condition still applies: the machine has to be logged
in (a locked screen is fine).

## Operating it

```sh
cd ~/actions-runner-personal-crm
./svc.sh status
./svc.sh stop        # pause CI without unregistering
./svc.sh start
gh run list --repo kevinzhang96/personal-crm --limit 5
gh workflow run deploy --repo kevinzhang96/personal-crm   # deploy without a code change
```

Note that `.github/**` and `**.md` are in `paths-ignore`: a commit that only
changes the pipeline or prose ships nothing and starts nothing, so the first
run after such a commit is a `workflow_dispatch`.
