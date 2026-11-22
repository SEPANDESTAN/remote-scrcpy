# Contributing and development

This is a personal project with a public mirror. Issues and pull requests
are welcome, but the maintainer's own use case decides what gets merged.
AI coding agents: start at [`AGENTS.md`](../AGENTS.md); everything below
applies to you too.

## What you need

- [Bash](https://www.gnu.org/software/bash/) 4.4 or newer (the tests run the
  bundle with whatever `bash` is first on `PATH`).
- An [OpenSSH](https://www.openssh.com/) client, [Android Platform Tools
  `adb`](https://developer.android.com/tools/releases/platform-tools) and
  [scrcpy](https://github.com/Genymobile/scrcpy) on `PATH`. The fast tests
  never contact a host or a phone, but a few checks resolve the executables.
- Optional: Python 3 for the integration fixture, root and an `sshd` binary to
  run it, and [shellcheck](https://github.com/koalaman/shellcheck) for static
  analysis.

## Get started

```bash
git clone https://github.com/SEPANDESTAN/remote-scrcpy.git
cd remote-scrcpy
unset "${!REMOTE_SCRCPY_@}"      # the suites inherit your launcher configuration
bash src/build.sh                # regenerates remote-scrcpy.sh (should be a no-op)
bash tests/test-maintenance.sh && bash tests/test-completion.sh \
  && bash tests/test-cli-ui-review.sh && bash tests/test-ssh-config.sh
```

Expected: 31, 10 and 23 passed checks and "SSH config discovery checks
passed." Details, the CI parity check and the integration suite are in
[`testing.md`](testing.md).

## Layout

| Path | Role |
|---|---|
| `remote-scrcpy.sh` | the only runtime file; **generated**, never edit by hand |
| `src/*.sh` | nine modules concatenated by `src/build.sh` in the order core, cli, ssh-config, presentation, ui, transport, prerequisites, completion, main |
| `tests/test-*.sh` | four fast suites, no network |
| `tests/*.py` | integration fixture: real OpenSSH and adb, simulated devices; needs root |
| `docs/` | this guide, [architecture](architecture.md), [testing](testing.md), [workflow](workflow.md), [release](release.md), [decisions](decisions.md), [history](history.md), the [2026-11-06 review](review-2026-11-06.md) |
| `AGENTS.md`, `.agents/`, `.claude/` | instructions and skills for AI coding agents |
| `.github/workflows/test.yml` | CI: syntax check, rebuild and diff the bundle, the four suites |

## Making a change

1. Edit the module under `src/`, not the bundle.
2. `bash src/build.sh`, then run the suites. Two suites test the bundle and
   two source the modules, so an unrebuilt change passes half of them.
3. Add or adjust tests in the suite that already covers the area
   (see the table in `testing.md`). Adding a CLI option touches more places
   than you expect; follow `.agents/skills/add-cli-option/SKILL.md`.
4. Update `README.md` if user-facing, and add a line under `## [Unreleased]`
   in `CHANGELOG.md` ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)).
5. Commit the regenerated `remote-scrcpy.sh` together with the `src/`
   change. CI diffs it against a fresh build.
6. Take the change to `main` through a pull request, as described in
   [`workflow.md`](workflow.md).

Never test transport changes by pointing the launcher at a real host from a
development shell; use fake `ssh`/`adb`/`scrcpy` programs on `PATH` (pattern
in `tests/test-completion.sh`).

## Conventions

- One public function, `remote-scrcpy`. Helpers are `_kebab-case` with
  explanatory names and a two-line comment: purpose, then arguments, side
  effects and failure behaviour.
- Globals are namespaced: `SETTINGS_*` (resolved configuration), `SESSION_*`
  (resources owned by the active connection, transport only),
  `DISCOVERED_DEVICE_*`, `DISPLAY_*`, `CLI_*`, `INPUT_RESPONSE`,
  `APPLICATION_VERSION`. The public interface is the `REMOTE_SCRCPY_*`
  environment variables and the CLI only.
- `local` for everything inside helpers; no `eval`; never execute anything
  from an SSH config; no new runtime dependencies and no bootstrap code that
  downloads or installs tools.
- stdout is data (listings, completion text); every message, prompt and
  banner goes to stderr.
- Example values in help and docs are synthetic: `remote-host`, `192.0.2.10`,
  `myuser`, `DEVICE1234567890`. Never a real alias, address, serial or model.
- Every external tool or standard gets its URL on first mention in markdown.
- Exit codes: 2 usage, 127 missing executable, 130 cancel, 143/129 signals,
  scrcpy's status otherwise (table in `architecture.md`).

## Commits and pull requests

[`workflow.md`](workflow.md) is the procedure: a worktree branch per change,
a draft pull request, an independent review, a squash merge, and the rules
for commit messages and version numbers.

## Static analysis

```bash
shellcheck -s bash remote-scrcpy.sh src/*.sh tests/*.sh
```

Expected false positives and their reasons are listed in `testing.md`; fix
anything else or justify it with a `# shellcheck disable=` comment.

## Releasing

See [`release.md`](release.md): the version lives in four places, and the
GitHub release notes carry a tag-pinned install URL.
