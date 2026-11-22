# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `AGENTS.md` as the entry point for AI coding agents, with `CLAUDE.md` as a
  symlink to it; shared skills under `.agents/skills/` (`build-and-test`,
  `add-cli-option`, `release`) linked from `.claude/skills`; a tracked
  `.claude/settings.json` that allowlists read-only and build/test commands.
- `docs/`: `CONTRIBUTING.md`, `architecture.md`, `testing.md`, `release.md`,
  `decisions.md`, `history.md`, and `review-2026-11-06.md` recording the
  adversarial review of 3.0.2 and its tracking issues (#2 to #8).
- `docs/workflow.md`: every change reaches `main` through a worktree branch,
  a pull request, an independent review and a squash merge; out-of-scope
  findings become issues; issue and pull request bodies follow the new
  templates under `.github/` and carry a type label.

### Changed
- README: the "Internal naming" and "Architecture for maintainers" sections
  moved to `docs/architecture.md`; a "Developing" section links every
  document under `docs/`; "Tests and limits" reduced to the commands.
- README install Option 2 uses `install -D` so the target directory is
  created when missing.
- `.gitignore` tracks the shared agent configuration and ignores only
  per-machine files (`.claude/settings.local.json`, `*.local.*`).

### CI
- The integration suite (real OpenSSH and adb, simulated phone) runs on every
  pull request and on every push to `main` in a second job, so
  `src/transport.sh` is exercised end to end before a change is merged. `actions/checkout` moves from v4 to
  v7.

### Tests
- The integration suite now fails for each transport mutation listed in
  issue #3, including a removed hex check on the length of the ADB version
  reply, an offline device accepted by serial, and the host-less socket form
  used through the tunnel (#3).
- Each check the ADB protocol probe makes on the content of a reply is
  tested on its own (a reply cut short, the status word, the length bounds,
  a short payload, a `FAIL` reply, the hex check on the version payload),
  and the device menu is tested to offer only ready devices (#15).

### Fixed
- The test suites no longer inherit the launcher's environment. With
  `REMOTE_SCRCPY_HOST` exported, one check used to run `ssh` against that
  host and three of the four fast suites failed; every suite and the
  integration fixture now clear `REMOTE_SCRCPY_*` and the generic fallback
  variables first (#4).
- The 3.0.2 changelog entry, the v3.0.2 release notes and issue #1 no longer
  quote the example values that the 3.0.2 cleanup removed.

### Compatibility
- No change to the launcher, its CLI, the `REMOTE_SCRCPY_*` variables or the
  bundle; `remote-scrcpy.sh` is byte-identical to 3.0.2.

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
