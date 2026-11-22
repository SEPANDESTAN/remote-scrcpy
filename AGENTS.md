# AGENTS.md

Instructions for AI coding agents working on **remote-scrcpy**. Humans: read
[`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) instead; it says the same
things in prose. `CLAUDE.md` is a symlink to this file, and `.claude/skills`
links to `.agents/skills`, so there is one copy of every instruction.

## What this project is

A single Bash executable, `remote-scrcpy.sh`, that runs
[scrcpy](https://github.com/Genymobile/scrcpy) on this computer against an
Android phone plugged into a different, SSH-reachable computer. It opens a
private SSH ControlMaster, forwards ports to the remote
[ADB](https://developer.android.com/tools/releases/platform-tools) server,
probes the ADB protocol, reserves a port with `adb forward tcp:0`, launches
scrcpy, and cleans everything up on exit or signal. Personal tool with a
public mirror: correctness, safety and honesty for the maintainer's own
daily use come first; polish for strangers second.

## Layout

| Path | Role |
|---|---|
| `remote-scrcpy.sh` | the only runtime file. **Generated.** Never edit it directly. |
| `src/build.sh` | concatenates the modules below into the bundle, in this order |
| `src/core.sh` `cli.sh` `ssh-config.sh` `presentation.sh` `ui.sh` `transport.sh` `prerequisites.sh` `completion.sh` `main.sh` | the source. `main.sh` holds the lifecycle; `transport.sh` owns every SSH/ADB/scrcpy resource |
| `tests/test-*.sh` | four fast suites, no network, run by CI |
| `tests/*.py` | integration fixture (real OpenSSH and adb, simulated phone); needs root and `sshd`; run by CI in its own job |
| `docs/` | architecture, testing, workflow, release, decisions, history, the last review |
| `.agents/skills/` | step-by-step procedures: `build-and-test`, `add-cli-option`, `release` |
| `.github/workflows/test.yml` | CI: `bash -n`, rebuild-and-diff the bundle, the four suites, and the integration suite in a second job |

## Rules

1. **Edit `src/`, run `bash src/build.sh`, commit the regenerated bundle in
   the same commit.** CI rebuilds and diffs `remote-scrcpy.sh`; a stale
   bundle fails. Two suites test the bundle and two source the modules, so
   an unrebuilt change passes half the tests.
2. **Never run the launcher against a real host or phone from a work
   session.** No `remote-scrcpy HOST`, no `--list-devices HOST`, no Tab
   completion with a real alias, unless `ssh`, `adb` and `scrcpy` on `PATH`
   are fakes you wrote (pattern: `tests/test-completion.sh`; recipe:
   `docs/testing.md`). Safe anywhere: `--help`, `--version`,
   `--prerequisites`, `--completion bash`, `--list-hosts`.
3. **Keep the suites deaf to your environment.** Each one starts by
   clearing `REMOTE_SCRCPY_*` and the generic fallbacks, and a maintenance
   check fails if a suite stops doing so; a new suite must do the same.
4. **No `eval`, no executing anything from an SSH config, no new runtime
   dependencies, no code that downloads or installs tools.** The bundle must
   stay plain Bash 4.4 plus OpenSSH, adb and scrcpy. `tests/test-maintenance.sh`
   greps for things that were removed on purpose (`gum`, `--ui=`, base64
   payloads) and must keep failing if they return.
5. **stdout is data, stderr is messages.** Listing and completion output is
   plain; prompts, banners and status go to stderr.
6. **Never terminate or restart a shared remote ADB server.** The protocol
   probe in `src/transport.sh` exists for this; do not replace it with adb
   client calls. `tcp:PORT` is used only to start the remote daemon;
   everything through the tunnel uses `tcp:127.0.0.1:PORT`.
7. **Keep examples synthetic:** `remote-host`, `192.0.2.10`, `myuser`,
   `DEVICE1234567890`, `Test_Phone_A`. Never a real hostname, address,
   serial, device model or person. Never quote removed example values in
   changelog or release text either.
8. **Every external tool or standard gets its URL on first mention** in
   markdown.
9. **Every script that takes arguments answers `--help`; every function in
   `src/` carries a doc comment** (purpose line, then arguments, side
   effects, failure). The test suites take no arguments and say what they
   are in their header comment.

## Commands

```bash
bash src/build.sh                                   # regenerate the bundle
bash src/build.sh /tmp/rebuilt.sh && diff -u /tmp/rebuilt.sh remote-scrcpy.sh   # CI parity
bash -n remote-scrcpy.sh
bash tests/test-maintenance.sh      # Maintenance checks: 58 passed.
bash tests/test-completion.sh       # Completion checks: 34 passed.
bash tests/test-cli-ui-review.sh    # CLI/menu review checks: 31 passed, 0 failed.
bash tests/test-ssh-config.sh       # SSH config discovery checks passed.
sudo REAL_ADB="$(command -v adb)" python3 tests/test_launcher_integration.py -v   # root + sshd; CI runs it too
```

## Conventions

- One public function, `remote-scrcpy`; helpers are `_kebab-case`.
- Globals: `SETTINGS_*` resolved configuration, `SESSION_*` connection
  resources (transport only), `DISCOVERED_DEVICE_*`, `DISPLAY_*`, `CLI_*`,
  `INPUT_RESPONSE`, `APPLICATION_VERSION`. Public interface:
  `REMOTE_SCRCPY_*` environment variables and the CLI, nothing else.
- Exit codes: 2 usage, 127 missing executable, 130 cancel or SIGINT, 143
  SIGTERM, 129 SIGHUP, 1 runtime failure, scrcpy's own status otherwise.
- Adding an option touches `core.sh`, `cli.sh` (parser and three help
  blocks), `completion.sh`, the `build.sh` header, README, CHANGELOG and
  three test files. Follow `.agents/skills/add-cli-option/SKILL.md`.
- Version lives in `src/core.sh`, `tests/test-maintenance.sh`, `CHANGELOG.md`
  and the regenerated bundle. Follow `.agents/skills/release/SKILL.md`.

## Git

Follow [`docs/workflow.md`](docs/workflow.md): one worktree branch and one
pull request per change, an independent review, then a squash merge. Never
push to `main` and never rewrite published history. The same page says what
still needs the maintainer's request. Add this trailer to commits you
author: `Co-Authored-By: <agent name> <noreply@...>`.

## Where to read next

- `docs/architecture.md`: lifecycle, transport invariants and the reasons
  behind them, Bash floor, exit codes.
- `docs/testing.md`: what each suite covers, what is not covered, how to
  write a hermetic transport test.
- `docs/workflow.md`: branch, pull request, review and merge procedure.
- `docs/decisions.md` and `docs/history.md`: why things are this way.
- `docs/review-2026-11-06.md`: the last full review; its findings were filed
  as GitHub issues #2 to #8. Issue #1 is the maintainer's reminder to fill
  in site-specific prerequisites.

## Windows checkouts

`CLAUDE.md` and `.claude/skills` are symlinks. Run
`git config --global core.symlinks true` before cloning (needs Developer
Mode), or read `AGENTS.md` and `.agents/skills/` directly.
