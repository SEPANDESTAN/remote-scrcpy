# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
