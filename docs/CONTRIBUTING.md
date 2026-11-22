# Contributing and development

This is a personal project with a public mirror. Issues and pull requests
are welcome, but the maintainer's own use case decides what gets merged.

This page is the home of the project's rules, for people and for AI coding
agents alike. [`AGENTS.md`](../AGENTS.md) is the entry point for agents and
points here; it adds nothing a person needs.

## What you need

- [Bash](https://www.gnu.org/software/bash/) 4.4 or newer (the tests run the
  bundle with whatever `bash` is first on `PATH`).
- An [OpenSSH](https://www.openssh.com/) client, [Android Platform Tools
  `adb`](https://developer.android.com/tools/releases/platform-tools) and
  [scrcpy](https://github.com/Genymobile/scrcpy) on `PATH`. The fast tests
  never contact a host or a phone, but a few checks resolve the executables.
- Optional: Python 3 for the integration suite, root and an `sshd` binary to
  run it, and [shellcheck](https://github.com/koalaman/shellcheck) for static
  analysis.

## Get started

```bash
git clone https://github.com/SEPANDESTAN/remote-scrcpy.git
cd remote-scrcpy
bash src/build.sh                # regenerates remote-scrcpy.sh (should be a no-op)
(for suite in tests/test-*.sh; do bash "$suite" || exit; done)
```

[`testing.md`](testing.md) has what a passing and a failing suite look like,
what each one covers, the check CI adds, and the integration suite.

## Layout

| Path | Role |
|---|---|
| `remote-scrcpy.sh` | the only runtime file; **generated**, never edit by hand |
| `install.sh` | the installer users pipe from [curl](https://curl.se/); copies or downloads the bundle into a directory on `PATH`; not part of the bundle |
| `src/build.sh`, `src/*.sh` | the build script and the modules it concatenates ([`architecture.md`](architecture.md) lists them) |
| `tests/test-*.sh` | the fast suites: no network, no phone, no root |
| `tests/*.py` | the integration suite and its fixtures: real OpenSSH and adb, simulated devices; needs root; CI runs it in its own job |
| `docs/` | this guide, [architecture](architecture.md), [testing](testing.md), [workflow](workflow.md), [adding a CLI option](adding-a-cli-option.md), [release](release.md), [decisions](decisions.md), the [2026-11-06 review](review-2026-11-06.md) |
| `AGENTS.md`, `.agents/`, `.claude/` | entry point and skills for AI coding agents |
| `.github/` | CI (`workflows/test.yml`) and the issue and pull request templates |

## Making a change

1. Edit the module under `src/`, not the bundle.
2. `bash src/build.sh`, then run the suites.
3. Add or adjust tests in the suite that already covers the area (table in
   [`testing.md`](testing.md)). A new command-line option touches more
   places than it seems to: follow
   [`adding-a-cli-option.md`](adding-a-cli-option.md).
4. Update `README.md` if the change is visible to users, and add a line
   under `## [Unreleased]` in `CHANGELOG.md`
   ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)).
5. Take the change to `main` through a pull request, as described in
   [`workflow.md`](workflow.md).

## Rules

1. **The bundle is generated.** Edit `src/`, run `bash src/build.sh`, and
   commit the regenerated `remote-scrcpy.sh` in the same commit. CI rebuilds
   it and fails on any difference, and an unrebuilt change is only half
   tested ([`testing.md`](testing.md)).
2. **Never run the launcher against a real host or phone from a development
   session**, whether you are a person trying a change or an agent: no
   `remote-scrcpy HOST`, no `--list-devices HOST`, no Tab completion with a
   real alias. Put fake `ssh`, `adb` and `scrcpy` programs first on `PATH`
   (pattern: `tests/test-completion.sh`) or use the integration suite. Safe
   anywhere: `--help`, `--version`, `--prerequisites`, `--completion bash`,
   `--list-hosts`.
3. **The suites are deaf to your environment.** Each fast suite begins by
   clearing the launcher's environment variables and closing its standard
   input; a new suite must do the same. The reasons, one of them a machine
   brought down by a test, are under "Environment" in
   [`testing.md`](testing.md).
4. **The launcher stays plain.** No `eval`, nothing executed from an SSH
   configuration, no new runtime dependency beyond Bash, OpenSSH, adb and
   scrcpy, and no code that downloads or installs tools. `install.sh` is
   the one narrow exception: it downloads the bundle itself and installs
   nothing else. `tests/test-maintenance.sh` searches the bundle for things
   that were removed on purpose (`gum`, `--ui=`, base64 payloads) and must
   keep failing if they return.
5. **stdout is data, stderr is messages.** Listings and the completion
   script are plain text on stdout; every prompt, banner, status line and
   error goes to stderr.
6. **Never terminate or restart a shared remote ADB server.** The protocol
   probe in `src/transport.sh` exists for this; do not replace it with adb
   client calls. `tcp:PORT` is used only to start the remote daemon, and
   everything through the tunnel uses `tcp:127.0.0.1:PORT`.
   [`architecture.md`](architecture.md) explains both.
7. **Examples are synthetic:** `remote-host`, `192.0.2.10`, `myuser`,
   `DEVICE1234567890`, `Test_Phone_A`. Never a real host name, address,
   serial, device model or person, and never a quotation of an example value
   that was removed, in a changelog, release note or issue either.
8. **Every external tool or standard gets its URL on first mention** in a
   markdown file.
9. **A script that a person runs with arguments answers `--help`** and
   refuses options it does not know: `remote-scrcpy.sh`, `install.sh`,
   `src/build.sh`; the integration suite answers through unittest. The fast
   suites take no arguments and say what they are in their header comment.
10. **Every function in `src/` carries one doc comment:** a purpose line,
    then arguments, side effects and failure behaviour.
11. **Every change reaches `main` through a reviewed pull request**, and
    published history is never rewritten. [`workflow.md`](workflow.md) is
    the procedure, including commit messages and version numbers.

## Conventions

- Names follow [`architecture.md`](architecture.md), "Internal naming": the
  one public function, how helpers are called, the prefixes of the globals,
  and what counts as the supported interface.
- `local` for every variable inside a helper.
- Every option has a long name. It may also have a one-letter form, and an
  older name may stay as an alias. `--help` lists every form. Documents
  show the long form first and the short one after it.
- Exit statuses follow the table in [`architecture.md`](architecture.md),
  which `--help` repeats for users.

## Documentation rules

- **One home per fact.** Rules live on this page, procedures on the page
  named after them (`workflow.md`, `testing.md`, `release.md`,
  `adding-a-cli-option.md`), how the program works in `architecture.md`, and
  why in `decisions.md`. Everything else links there and does not restate
  it. If you find the same thing written twice, delete one copy.
- **`docs/` is for people and agents alike.** `AGENTS.md`, `.agents/` and
  the skills are indexes for agents: they route to these pages and add only
  what applies to agents alone.
- **No numbers that every change moves.** Do not write how many checks a
  suite has or how many lines a file has; say what the output looks like.
- **Dated records are not edited.** `review-2026-11-06.md` describes the
  repository on that day. Decisions are appended to `decisions.md`; an
  existing entry is changed only to correct or complete its facts, or to
  fix a reference that has gone stale.
- `README.md` is for users: install, usage, limits. `CHANGELOG.md` records
  what changed for them.

## Static analysis and releasing

shellcheck is not part of CI; how to run it and which findings are expected
is in [`testing.md`](testing.md). Cutting a version is in
[`release.md`](release.md).
