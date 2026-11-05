# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Moved the nine bundled source modules and `build.sh` under `src/` so the repo
  root stays limited to user-facing files (`README.md`, `LICENSE`,
  `CHANGELOG.md`, the `remote-scrcpy.sh` artifact, `tests/`, `.github/`).
- Rewrote the README opening with explicit **Install** and **Usage** sections,
  including `curl` and `git clone` recipes pointing at
  `SEPANDESTAN/remote-scrcpy` on GitHub.

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
