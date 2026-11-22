# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `install.sh`: `curl -fsSL .../install.sh | bash` puts the launcher in
  `~/.local/bin`, after checking that the file parses and runs. `--dir`
  chooses the directory, `--ref` a tag or branch, and `--completion` adds
  Bash completion to `~/.bashrc` as one marked line. From a checkout it
  installs that checkout's bundle without network. No `sudo`, and nothing
  else is installed. Covered by a fifth fast suite, `tests/test-install.sh`.
- `--completion=bash` is accepted next to `--completion bash`, like the `=`
  form of every other option that takes a value; Tab completes it (#7).
- `AGENTS.md` as the entry point for AI coding agents, with `CLAUDE.md` as a
  symlink to it; shared skills under `.agents/skills/` (`build-and-test`,
  `add-cli-option`, `release`) linked from `.claude/skills`; a tracked
  `.claude/settings.json` that allowlists read-only and build/test commands.
- `docs/`: `CONTRIBUTING.md`, `architecture.md`, `testing.md`, `release.md`,
  `decisions.md`, and `review-2026-11-06.md` recording the adversarial
  review of 3.0.2 and its tracking issues (#2 to #8).
- `docs/workflow.md`: every change reaches `main` through a worktree branch,
  a pull request, an independent review and a squash merge; out-of-scope
  findings become issues; issue and pull request bodies follow the new
  templates under `.github/` and carry a type label.

### Changed
- Documentation has one home per fact under `docs/`. `CONTRIBUTING.md` holds
  every rule and a section on how the documents are kept; the option
  checklist moved from a skill to `docs/adding-a-cli-option.md`; the skills
  point at the documents and no longer copy them; no document states how
  many checks a suite has; `docs/history.md` is removed, and the two facts
  only it held are now in `docs/decisions.md`; `docs/architecture.md` lists
  the upstream sources its invariants rely on; the README's "Developing"
  section is a pointer, and "Tests and limits" became "Limits" with a new
  note on `stty tostop` (#13, #6).
- Source comments: every module has one header and every function one doc
  comment. Most modules opened with two overlapping headers and a few
  functions carried two or three stacked comments. Comments that were wrong
  are corrected: which of colors and symbols need a terminal, which
  functions assign the session variables, and why cleanup leaves a forward
  behind once scrcpy has taken over the reserved port (#6). No code line
  changes.
- `bash src/build.sh --help` prints its usage. Before, any option was taken
  for the output path and failed inside `mktemp`; unknown options and extra
  arguments are now refused with status 2 (#5).
- `--help` describes what the launcher refuses after `--`, gives the range
  of `REMOTE_SCRCPY_COMPLETION_TIMEOUT`, and has an EXIT STATUS section that
  separates the launcher's statuses from scrcpy's. `--prerequisites` and the
  README name `cat` and `env` among the required utilities and the
  `/dev/tcp` and `/tmp` requirements. The README also says that completion
  uses the default remote ADB port, names the fallback variables, and
  explains what loopback tunnels mean on a shared machine (#7, #8).
- Error messages name every place a rejected value can come from: an
  invalid toggle its variable (`REMOTE_SCRCPY_ASCII`, not an internal name),
  and the port, the color mode and the remote adb both the option and the
  variables. The troubleshooting list quotes "ADB protocol mismatch" as the
  error itself does, and a refused scrcpy option that may be a value says to
  write `--option=value` (#7).
- A launcher run now checks for `cat` and `env` up front along with the
  other utilities, instead of failing later (#7).
- `--color=always` and `REMOTE_SCRCPY_COLOR=always` now color the output
  even when `NO_COLOR` is set. `NO_COLOR` used to win over everything; the
  [NO_COLOR](https://no-color.org/) convention asks that a setting made for
  the program itself overrides it. With the mode left at `auto`, `NO_COLOR`
  still disables color.
- README: the "Internal naming" and "Architecture for maintainers" sections
  moved to `docs/architecture.md`; a "Developing" section points to the
  contributing guide.
- README install Option 2 uses `install -D` so the target directory is
  created when missing.
- `.gitignore` tracks the shared agent configuration and ignores only
  per-machine files (`.claude/settings.local.json`, `*.local.*`).

### Removed
- The aliases `--list` (for `--list-devices`) and `--requirements` (for
  `--prerequisites`). They were accepted but never documented, although Tab
  completion offered `--list` up to 3.0.2, where it did not say which list;
  both now fail as unknown options (#7).

### CI
- The integration suite (real OpenSSH and adb, simulated phone) runs on every
  pull request and on every push to `main` in a second job, so
  `src/transport.sh` is exercised end to end before a change is merged. `actions/checkout` moves from v4 to
  v7.

### Tests
- The maintenance suite fails, naming the file, when a module under `src/`
  is missing from the bundle. The rebuild comparison in CI cannot show such
  a loss, and the fast suites noticed it only for modules they happen to
  call: without `ui.sh` or `transport.sh` all four passed, and only the
  integration suite failed (#6).
- The integration suite now fails for each transport mutation listed in
  issue #3, including a removed hex check on the length of the ADB version
  reply, an offline device accepted by serial, and the host-less socket form
  used through the tunnel (#3).
- Each check the ADB protocol probe makes on the content of a reply is
  tested on its own (a reply cut short, the status word, the length bounds,
  a short payload, a `FAIL` reply, the hex check on the version payload),
  and the device menu is tested to offer only ready devices (#15).

### Fixed
- Tab completion no longer offers device serials for the first positional
  when `REMOTE_SCRCPY_HOST` is set. The launcher reads that position as the
  host, so an accepted suggestion was used as an SSH destination. Completion
  now follows the launcher: the first positional is the host and replaces
  the environment host for device lookups; `--serial <Tab>` completes a
  serial for the environment host (#2).
- Tab completion no longer misreads words that contain `=`, `@` or `:`. Bash
  splits the line at those characters before calling a completion function,
  so `--serial=D` was read as an option, its value `=` and a positional, and
  a serial, a port number or a user name could end up as the host that
  completion contacted. `--host=`, `--serial=` and `--color=` now complete
  in an interactive shell, serials that contain a colon complete, and a
  `user@host` destination is read as one host (#20).
- `--help`, `--version`, `--prerequisites`, `--completion bash` and
  `--list-hosts` no longer fail when `HOME` is not set. The home directory
  is then taken from the password database, where OpenSSH looks too, so the
  alias list is the same as with `HOME` set. With an empty `HOME` there is
  no default SSH config, and an `Include` that needs a home directory is
  skipped with a message.
- Closing the terminal no longer kills scrcpy outright. The launcher passed
  the hangup signal on unchanged, and scrcpy, which handles only interrupt
  and terminate, died before its own shutdown, for example without finishing
  a recording; it now receives a terminate signal and shuts down, and the
  launcher still exits with status 129 (#6).
- A device lookup started by Tab no longer reads from the terminal. Keys
  typed while it ran were taken by `ssh` and sent to the remote instead of
  reaching the shell; where a `timeout` program is installed, the lookup was
  instead stopped by that read, and Tab hung until the time limit and
  offered nothing (#8).
- The test suites no longer inherit the launcher's environment. With
  `REMOTE_SCRCPY_HOST` exported, one check used to run `ssh` against that
  host and three of the four fast suites failed; every suite and the
  integration fixture now clear `REMOTE_SCRCPY_*` and the generic fallback
  variables first (#4).
- The 3.0.2 changelog entry, the v3.0.2 release notes and issue #1 no longer
  quote the example values that the 3.0.2 cleanup removed.

### Compatibility
- No documented option or `REMOTE_SCRCPY_*` variable was removed or renamed;
  the two aliases removed above were never documented. Two behaviours
  changed:
- Tab completion with `REMOTE_SCRCPY_HOST` exported: the first positional
  now completes as a host, as the launcher reads it. To complete a serial on
  the environment host, use `--serial <Tab>` or `--serial=<Tab>`.
- `NO_COLOR` together with an explicit `--color=always` or
  `REMOTE_SCRCPY_COLOR=always`: the output is now colored.

## [3.0.2] — 2026-11-05

### Changed
- Moved the nine bundled source modules and `build.sh` under `src/` so the repo
  root stays limited to user-facing files (`README.md`, `LICENSE`,
  `CHANGELOG.md`, the `remote-scrcpy.sh` artifact, `tests/`, `.github/`).
- Rewrote the README opening with explicit **Install** and **Usage** sections,
  including `curl` and `git clone` recipes pointing at
  `SEPANDESTAN/remote-scrcpy` on GitHub.
- Replaced a brand-specific example SSH alias with the generic `remote-host`
  across CLI help, prerequisites guide, README, bundled HEADER, and all test
  fixtures.
- Replaced a realistic-looking Android serial and OEM model strings with the
  synthetic `DEVICE1234567890` / `test` / `Test_Phone_A` placeholders.
- Linked each externally-maintained tool and standard on first mention in the
  README: [scrcpy](https://github.com/Genymobile/scrcpy),
  [Bash](https://www.gnu.org/software/bash/),
  [OpenSSH](https://www.openssh.com/),
  [ADB / Android Platform Tools](https://developer.android.com/tools/releases/platform-tools),
  and [NO_COLOR](https://no-color.org/).
- Documented that the installable artifact can live in any directory on
  `$PATH`, not only `$HOME/.local/bin`.
- Added a prominent pointer from both `--prerequisites` and the README to
  [issue #1](https://github.com/SEPANDESTAN/remote-scrcpy/issues/1), which
  tracks the site-specific prerequisites expansion.
- Attributed the LICENSE copyright line to the SEPANDESTAN organization.

### CI
- Pinned the tests workflow to `permissions: contents: read` and added
  `workflow_dispatch:` for manual reruns from the Actions tab.

### Compatibility
- No change to the public CLI, the `REMOTE_SCRCPY_*` environment variables,
  or the install path for the single-file executable.
- `bash build.sh` becomes `bash src/build.sh` for maintainers who rebuild
  the bundle locally.

## [3.0.1] — 2026-11-04

### Changed
- Renamed internal shell variables from the opaque `RS_*` / `RS_T_*` prefixes
  to descriptive, scoped names: `SETTINGS_*` (resolved configuration),
  `SESSION_*` (connection resources), `DISCOVERED_DEVICE_*` (parallel device
  arrays), `DISPLAY_*` (terminal styles), `CLI_*` (explicit-argument flags),
  and `INPUT_RESPONSE` (last prompt answer).
- Expanded the generated executable's file-level header and the shared-state
  contracts documented in `core.sh` and `transport.sh`.

### Compatibility
- The public command-line interface is unchanged.
- All documented `REMOTE_SCRCPY_*` environment variables continue to work.
