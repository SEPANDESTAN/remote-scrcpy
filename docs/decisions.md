# Decision log

Why the project is the way it is. One entry per decision, oldest first. Entries
marked *pre-import* were taken before the repository was published on
2026-11-05 and are reconstructed from the code and its comments; their exact
dates are not recorded.

Format: **Decision.** Why. Consequences / where it shows in the code.

## Pre-import

- **Ship one Bash file, built from modules.** Installing is copying one file;
  maintaining is editing small modules. `src/build.sh` concatenates the nine
  modules under `src/` in a fixed order into `remote-scrcpy.sh`, which is
  committed. CI rebuilds and diffs it, so a stale bundle fails the build.
- **No TUI framework, no `--ui` flag, no embedded payload.** An earlier
  iteration used the `gum` TUI tool and a base64-encoded payload; both were
  removed so the launcher has no dependency beyond Bash, OpenSSH, adb and
  scrcpy. `tests/test-maintenance.sh` greps the bundle for `gum`, `--ui=` and
  `base64 --decode` so they cannot come back by accident.
- **Bash 4.4 is the floor.** Empty arrays expanded under `set -u` (for example
  the scrcpy pass-through arguments) only work from 4.4. The bundle checks
  `BASH_VERSINFO` before any other statement and exits 2, so macOS's
  `/bin/bash` 3.2 fails cleanly instead of with a parse error.
- **One private SSH ControlMaster per run, socket under `/tmp`.** The master
  is opened with `ssh -fMNT`, every later operation goes through `-O`
  control commands, and the mux client runs with `-F /dev/null -o
  ProxyCommand=false` so it can never fall back to a fresh connection. The
  directory comes from `mktemp -d /tmp/remote-scrcpy.XXXXXXXX` and ignores
  `TMPDIR` on purpose: Unix socket paths are limited to about 108 bytes.
- **Probe the remote ADB protocol over `/dev/tcp`, never with the adb client.**
  An adb client that meets a server of a different protocol version kills
  and restarts that server. The remote server may be shared with other
  users, so the launcher reads `host:version` itself and refuses to continue
  on a mismatch. Rule stated in the README: never terminate a shared remote
  ADB server.
- **`tcp:PORT` only when starting the remote daemon, `tcp:127.0.0.1:PORT`
  through the tunnel.** adb treats a host-less `tcp:PORT` as local and may
  start a server for it; a `127.0.0.1` address is treated as remote and never
  starts one. Local adb and scrcpy are always pointed at the tunnel form.
- **Reserve the remote media port with `adb forward tcp:0` and a unique
  token.** `tcp:0` lets adb pick a free port atomically. The token
  (`localabstract:remote_scrcpy_<workdir>_<random>`) is what cleanup matches
  on, so a port that another session obtained later is never removed.
  Consequence: if scrcpy has already rebound the port and then dies without
  its own cleanup, that forward is left behind on the remote until the ADB
  server restarts. Accepted as the safer side of the trade-off.
- **scrcpy gets its own process group through `set -m`.** Ctrl-C reaches the
  launcher only, which forwards exactly one signal, waits, then escalates to
  the group. No `setsid` dependency.
- **Stdout is data, stderr is messages.** Listing modes print plain
  tab-separated data; every prompt, banner and status line goes to stderr so
  the launcher composes in pipelines.
- **SSH config is read as data, never interpreted.** Host alias discovery
  parses `Host` and `Include` lines only. `Match`, `ProxyCommand` and friends
  are never evaluated; OpenSSH stays the authority for the real connection.

## 2026-11-04

- **Rename the internal `RS_*` prefix to descriptive namespaces** (`SETTINGS_*`,
  `SESSION_*`, `DISCOVERED_DEVICE_*`, `DISPLAY_*`, `CLI_*`, `INPUT_RESPONSE`).
  Released as 3.0.1. The public interface stays `REMOTE_SCRCPY_*` only.

## 2026-11-05

- **Publish under the SEPANDESTAN GitHub organization, MIT licensed, with the
  organization as copyright holder.**
- **Move the modules under `src/`.** The root should show as few shell scripts
  as possible; the only runtime file at the root is the bundle.
- **Lead the README with Install and Usage.** A visitor should be able to copy
  one block and run the tool.
- **Use only synthetic example values.** `remote-host` as the SSH alias,
  `192.0.2.10` (RFC 5737 TEST-NET-1), `myuser`, `DEVICE1234567890`,
  `Test_Phone_A`. Nothing tied to a real host, phone or person.
- **Track site-specific setup as a questionnaire in issue #1** instead of
  inventing instructions for hardware and operating systems that were not
  verified.
- **CI token gets `contents: read` only, plus `workflow_dispatch`.**

## 2026-11-06

- **Acceptance standard: a personal tool with a public mirror.** It must be
  correct, safe and honest for the maintainer's own daily use across future
  machines. GitHub presentation only needs to not embarrass. Missing
  contributor scaffolding is not a defect.
- **Keep git history as it is.** The initial import still contains the
  pre-sanitization example values. Rewriting history was judged not worth
  invalidating the v3.0.2 tag. Quoting those values in a changelog, release
  note or issue *is* a defect and was fixed on 2026-11-19.
- **Every script should answer `--help`, every function carries a doc
  comment, and the repository must document itself well enough that a new
  AI coding agent can start work from the docs alone.** The onboarding files
  added on 2026-11-19 implement the last point; the `--help` gap is tracked
  as an issue.
- **Fixes to review findings are tracked as issues, not folded into the
  review.** See `review-2026-11-06.md`.

## 2026-11-19

- **`AGENTS.md` is the single agent entry point; `CLAUDE.md` is a symlink to
  it.** Skills live under `.agents/skills/` and `.claude/skills` is a symlink
  to that directory, so there is one copy of every instruction. Windows
  checkouts need `git config core.symlinks true`.
- **Long-form context lives under `docs/`**, readable by humans and agents
  alike; `AGENTS.md` and the README only point there.
- **A shared `.claude/settings.json` allowlists read-only and build/test
  commands only.** Anything that writes (commits, pushes, GitHub edits) still
  prompts. Per-machine overrides stay in the ignored `settings.local.json`.

## 2026-11-22

- **Every change reaches `main` through a reviewed, squash-merged pull
  request.** Until now commits went straight to `main`, which left nobody
  but the author to catch a mistake. Each change gets a worktree branch, a
  draft pull request, a self-review, a review by someone who did not write
  it (for agent-written changes, an agent with a fresh context), and a
  squash merge whose message is written as documentation. History is never
  rewritten. The procedure is `workflow.md`.
- **"Small commits ordered leaf to root" becomes "pull requests ordered leaf
  to root".** A squash merge leaves one commit per pull request on `main`,
  so the order of commits inside a branch no longer reaches the history.
  The ordering rule now applies to the pull requests of a series.
- **Transport coverage comes from the existing integration suite in CI, not
  from a second, fake-ssh suite.** Issue #3 proposed a new hermetic suite
  built on fake `ssh`, `adb` and `scrcpy` programs. The repository already
  had a suite that drives the real launcher through a real `sshd` and adb
  client; it was simply never run. On a GitHub runner it needs two packages
  and `sudo`, so it runs there as its own job. Measured against the seven
  mutations of issue #3 it caught five where the fast suites catch none; the
  other two got tests of their own instead of a second infrastructure.
- **Releases go through a pull request too.** The release commit used to be
  pushed to `main`; `release.md` now puts it on a `release/X.Y.Z` branch.
- **The undocumented aliases `--list` and `--requirements` are dropped, not
  documented.** Issue #7 offered both ways out. Decided with the maintainer
  while approving the review plan: one name per thing, and nothing had ever
  documented them, so removing them breaks no stated interface. If either
  turns out to be in use, it comes back as a documented option.
- **`--help` is required of scripts that take arguments, not of every
  script.** The 2026-11-06 standard said every script should answer
  `--help` and every function carry a doc comment, and issue #5 listed what
  was missing: the build script, the four test suites, the three Python
  fixtures, and seventeen test helpers. Only the build script takes an
  argument, and it misread `--help` as an output path. It now explains
  itself. The suites take no arguments and state their purpose in their
  first lines; the fixtures are a library and two stand-ins driven by the
  integration suite, each with a module docstring. Giving them option
  parsing, and one-line helpers such as `fail` a comment, would add text
  that tells a reader nothing. The doc-comment rule stays for `src/`.
