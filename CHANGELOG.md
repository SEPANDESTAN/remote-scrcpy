# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `install.sh`: `--version VERSION` (`-v`) chooses what to download and
  takes a release number with or without its `v` (`3.1.0`, `v3.1.0`) or a
  branch; `--with-tab-completion` (`-c`) adds Bash completion; `-d` is short
  for `--dir`. The names of 3.1.0, `--ref` and `--completion`, still work
  and are listed in `--help`.
- One-letter forms for the options used every day: `-l` for
  `--list-devices`, `-L` for `--list-hosts`, `-p` for `--prerequisites`,
  `-q` for `--quiet` and `-n` for `--non-interactive`, next to `-h`. `--help`
  lists each beside its long name, and Tab on a word that starts with a
  dash offers the options, short and long. Before, `remote-host -<Tab>`
  fell through to a device lookup on the host.
- Tab completes in more places: file names after `--ssh-config=`, `--adb=`
  and `--remote-adb=` (only the forms with a space did), and host aliases
  after a user name, as in `remote-scrcpy myuser@r<Tab>` (#23).

### Changed
- Numbers that come from the remote ADB server are converted with `printf`
  where the launcher used shell arithmetic: the two hexadecimal fields of
  the version reply, and the port the server reports for a reservation.
  Arithmetic can run a command hidden in what it is given, and one check on
  the line before was all that kept remote data out of it; `printf` runs
  nothing, so the conversion is safe by itself. A version field longer than
  eight hex digits and a reported port that is not a port are now covered
  by tests (#16).
- `docs/workflow.md` says how an issue and a pull request end: an issue may
  be closed as not planned with its reason recorded, and a pull request may
  be an experiment that is closed unmerged. The merge conditions are stated
  once, the page warns that a closing keyword works anywhere in a body, and
  the section on stacked pull requests is rewritten from what a real pair
  showed: retarget the upper one before deleting the lower branch (#10).

### Tests
- Standard output is checked to stay plain: with color forced on, by the
  option or by the environment, `--help`, `--version`, `--prerequisites`,
  `--completion bash` and `--list-hosts` write no terminal escape to it.
  In the integration suite neither does `--list-devices` nor a connecting
  run, and the host menu writes nothing there at all. The automatic color
  mode is tested on a terminal: it colors, obeys a `NO_COLOR` that has a
  value, ignores an empty one, and leaves a dumb terminal alone; so are
  the Unicode marks and the order in which the locale variables are read.
  The test for a terminal is a one-line function in `src/presentation.sh`
  that the fast suite answers for; the integration suite runs the real
  one, with a pseudo-terminal on standard error only and on the other
  streams only (#27).
- Every check in the fast suites says what failed, and so do the discovery
  and completion calls that run before a check. Eleven checks in
  `tests/test-ssh-config.sh` were bare tests that ended the suite with
  status 1 and no output, and so did a discovery or a completion call that
  returned non-zero before its check, in that suite and in two others. The
  two checks that the caller's glob settings survive a discovery could not
  fail, because the discovery ran in a command substitution; it is called
  directly now (#38).

### Fixed
- Text from the phone and the remote is cleaned of the eight-bit control
  characters (U+0080 to U+009F) as well, before it is shown. They arrive
  as UTF-8, where the cleaning let them through, and some terminals obey
  them like their escape forms: in a terminal built on VTE, as GNOME's
  are, the model name a phone reports could set the window title or start
  a control sequence. In an eight-bit locale the bare bytes are replaced
  too. Letters of other scripts are untouched (#53).
- With `LC_ALL` naming a locale that is not installed, the launcher no
  longer adds a `setlocale` warning of its own to the one Bash prints when
  it starts. The warning came from the function that cleans text before
  it is shown, each time it put the caller's locale back.
- A number written in the digits of another script (Arabic-Indic, for one)
  is treated like any other text that is not a number. In some locales,
  `en_US.UTF-8` among them, the launcher's checks let such digits through,
  and the run then ended in a Bash arithmetic error. Now a remote ADB port
  given that way is a usage error with status 2 (it was the Bash error with
  status 1), the device menu asks again, and the host menu takes the text
  as the name of a destination, as it does in other locales. Every number
  check in the launcher and in `install.sh` names the ten ASCII digits
  (#50).
- `install.sh --version main` is no longer refused under a Turkish locale,
  where the letter range the check used does not contain `i`; a name with
  `y` met the same under a Latvian one. The check names its letters.
- A missing `adb` or `scrcpy` is reported with every way to give its path:
  `--adb`, `REMOTE_SCRCPY_ADB` or the fallback `ADB` for adb, and
  `REMOTE_SCRCPY_SCRCPY` or the fallback `SCRCPY` for scrcpy, which has no
  option. The message used to end in "Install it or specify its path."
  without saying how (#30).
- Two mode options on one command line are now refused whichever two they
  are and in whichever order. Before, `--completion=bash --list-hosts`
  failed while `--list-hosts --completion=bash` printed the completion
  script and ignored the listing, and `--prerequisites` silently won or
  lost depending on where it stood (#32).

### Compatibility
- **`-v` and `-V` have swapped.** `-v` now prints the version and `-V` turns
  on verbose output, as in scrcpy; until 3.1.0 it was the other way round.
  A script that passes `-v` for verbose output gets the version and status
  0 instead of a connection: write `--verbose` or `-V`. In the other
  direction, `-V` used to print the version and stop; it now goes on with
  the run, which is a connection when a host and serial are given or
  exported: write `--version` or `-v`.
- `-n` before the `--` used to be refused as an unknown option. It is also
  scrcpy's no-control option, so `remote-host DEVICE1234567890 -n`, typed
  without the `--`, is no longer an error: it is the launcher's
  `--non-interactive`, with control on. Write `-- -n` for scrcpy's. A
  forgotten `--` in front of scrcpy's `-p PORT` is still refused.
- `--prerequisites` and `--completion` no longer accept a host or serial
  next to them; `--list-hosts` already refused one. A second mode option is
  always an error, also the same one twice. The refusal of scrcpy options
  next to a mode names the option ("--prerequisites does not take scrcpy
  options.") where it said "Listing modes" for all four.

## [3.1.0] — 2026-11-22

### Added
- `install.sh`: `curl -fsSL .../install.sh | bash` puts the launcher in
  `~/.local/bin`, after checking that the file parses and runs. `--dir`
  chooses the directory, `--ref` a tag or branch, and `--completion` adds
  Bash completion to `~/.bashrc` as one marked line. From a checkout it
  installs that checkout's bundle without network. No `sudo`, and nothing
  else is installed. Covered by a fifth fast suite, `tests/test-install.sh`.
  The README's Install section leads with it and keeps the steps to install
  by hand.
- `--completion=bash` is accepted next to `--completion bash`, like the `=`
  form of every other option that takes a value; Tab completes it (#7).
- `AGENTS.md` as the entry point for AI coding agents: an index into `docs/`
  with three rules repeated. `.agents/rules.md` holds what applies to agents
  only. Shared skills under `.agents/skills/` (`build-and-test`,
  `add-cli-option`, `pull-request`, `release`), each a pointer to its
  document, linked from `.claude/skills`; a tracked `.claude/settings.json`
  that allowlists read-only and build/test commands.
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
  many checks a suite has; `docs/architecture.md` lists the upstream sources
  its invariants rely on; the README's "Developing" section is a pointer,
  and "Tests and limits" became "Limits" with a new note on `stty tostop`
  (#13, #6).
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
  `src/transport.sh` is exercised end to end before a change is merged.
  `actions/checkout` moves from v4 to v7.

### Tests
- Every fast suite closes its standard input as well as clearing the
  launcher's environment, and the maintenance suite checks both. A draft of
  the new installer suite, before it was merged, started a shell with a
  socket on standard input and a stripped `PATH`; that shell took itself
  for a remote shell, read the user's startup files, and forked without
  end.
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
  skipped with a message. A `HOME` that is not an absolute path now counts
  as no home directory, where 3.0.2 used it as given.
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
- No documented option or `REMOTE_SCRCPY_*` variable was removed or
  renamed. Three behaviours changed:
- `--list` and `--requirements` are gone; use `--list-devices` and
  `--prerequisites`. Neither alias was in `--help` or the README, but Tab
  completion offered `--list` up to 3.0.2.
- Tab completion with `REMOTE_SCRCPY_HOST` exported: the first positional
  now completes as a host, as the launcher reads it. To complete a serial on
  the environment host, use `--serial <Tab>` or `--serial=<Tab>`.
- `NO_COLOR` together with an explicit `--color=always` or
  `REMOTE_SCRCPY_COLOR=always`: the output is now colored. The help text of
  3.0.2 said that `NO_COLOR` disables color unconditionally; it now decides
  only while the color mode is `auto`.

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
