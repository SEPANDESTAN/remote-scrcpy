# Decision log

Why the project is the way it is. One entry per decision, oldest first. Entries
marked *pre-import* were taken before the repository was published on
2026-11-05 and are reconstructed from the code and its comments; their exact
dates are not recorded. Nothing else of the design history before that day
survives: the import commit carries version 3.0.1, so at least three major
iterations came before it, and the sessions with the AI coding agent that
produced most commits since are not preserved either. What mattered in them
is on this page and in the other documents.

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
  on a mismatch. The rule, never terminate a shared remote ADB server, is in
  `CONTRIBUTING.md`.
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
  verified. The maintainer still has to answer it before the `[TODO]`
  markers in `src/prerequisites.sh` and the matching README section can
  become instructions; it is the one standing reminder carried over from
  before the import.
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
- **`--help` is required of scripts a person runs with arguments, not of
  every script.** The 2026-11-06 standard said every script should answer
  `--help` and every function carry a doc comment, and issue #5 listed what
  was missing: the build script, the four fast suites, the three Python
  files, and seventeen test helpers. The build script takes an output path
  and misread `--help` as one; it now explains itself. The fast suites read
  no arguments and state their purpose in their first lines. Of the Python
  files, `test_launcher_integration.py` is the integration suite, which
  takes the options of unittest and answers `--help` through it, with its
  run command in the docstring; `native_adb_fixture.py` is an imported
  library; and `fake_scrcpy.py` is a stand-in that receives the scrcpy
  command line from the launcher under test, never from a person. Giving
  the suites and the stand-in option parsing, and one-line helpers such as
  `fail` a comment, would add text that tells a reader nothing. The
  doc-comment rule stays for `src/`.
- **An installer, `install.sh`, that does one thing.** Installing was four
  shell lines in the README, and completion a fifth to add by hand. The
  maintainer asked for a script that can be piped from
  `raw.githubusercontent.com` and also sets up completion. It copies or
  downloads the bundle, checks that the file parses and answers `--version`
  before it replaces anything, and with `--completion` appends one marked
  line to `~/.bashrc`, once. The line names the installed file, not the
  command, because a login shell can read `~/.bashrc` before the directory
  is on `PATH` (the stock `~/.profile` of Ubuntu does); a completion line
  that is already there for another place is reported and left alone, not
  rewritten. Kept out on purpose: `sudo`, installing `ssh`,
  `adb` or `scrcpy`, editing `PATH`, shells other than Bash, an uninstall
  command (delete one file and one line), and self-update. It is a separate
  file and not part of the bundle, so the rule that the launcher never
  downloads anything stands; the installer downloads the launcher and
  nothing else. Its work sits in a function called from a brace group on the
  last line, so a download cut short at any byte installs nothing.
- **`docs/` is the single source; the agent files are indexes.** By
  2026-11-22 the repository held about as much markdown as shell, with the
  same facts in up to five files: the build and test procedure in four, the
  module order in five, the pass counts of the suites in four. Every change
  had to update the copies, and they drifted. Decided with the maintainer:
  rules live in `CONTRIBUTING.md`, each procedure on its own page, and
  `AGENTS.md`, `.agents/` and the skills route to them and add only what
  applies to agents alone. Consequences in `docs/`: no pass counts anywhere;
  the option checklist moved from a skill to `adding-a-cli-option.md`;
  `history.md` is gone, because it restated `git log` up to the twelfth
  commit and the two facts only it held are now on this page (the
  introduction and the entry on issue #1); the README's developer sections
  shrank to pointers.
- **The recipe for a transport test built on fake programs is removed.**
  `testing.md` described how to source the modules and drive single
  transport functions against fake `ssh`, `adb` and `scrcpy` programs. No
  such test was ever written, the suite it sketched was declined in favour
  of the integration suite (entry above), and a page of instructions for
  code that does not exist misleads more than it helps.
- **Declined findings of the 2026-11-06 review**, so that nobody reopens
  them without a new reason. From issue #6:
  - *A terminal with `stty tostop` stops scrcpy at its first log line.*
    Documented as a limit in the README, not fixed: the fix is to pipe
    scrcpy's output through the launcher, which adds a process and changes
    how its output reaches the terminal, for a setting that is off by
    default.
  - *A forward channel refused by `sshd` is taken for "no remote daemon".*
    It needs a server that forbids forwarding, with which the launcher
    cannot work at all, and two adb versions on the remote. Telling the two
    apart would mean reading the SSH master's diagnostics.
  - *No fallback when the control socket is gone.* `-O exit` is the only
    handle on the master; a second one (its process ID) would cover the
    case of something else deleting a private directory under `/tmp` while
    a session runs.
  - *Rows that adb prints as `(no serial number)` are split wrongly.* Such a
    device cannot be selected by serial at all; the row is cosmetic and
    rare.

  From issue #8:
  - *UTF-8 C1 control characters pass the display sanitizer.* The strings
    come from the user's own remote machine and phone. Worth doing if the
    launcher is ever pointed at machines its user does not control.
  - *Tab is unbounded without the `timeout` program.* The README says the
    wrapper is used where installed; a bound written in Bash would be a
    second implementation of it.
  - *The SSH configuration tokenizer is quadratic.* It needs a `Host` line
    of tens of thousands of characters.
  - *`REMOTE_SCRCPY_COMPLETE_DEVICES` honours only `0`.* It is documented
    that way.
  - *`_resolve-executable-path` trusts `command -v`.* It needs an exported
    shell function named `adb` and a file of that name in the working
    directory.
  - *A literal `~` in the command word gives no host completions.* Tracked
    with the other completion quoting cases in issue #22.
