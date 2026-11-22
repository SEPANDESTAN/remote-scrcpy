# Adding a command-line option or environment variable

The launcher has no option table; each option is registered by hand in
several places. Missing one produces a flag that works but is invisible to
help or completion, or a CI failure. Work through every row.

## Code (`src/`)

| File | What to add |
|---|---|
| `src/core.sh` | A `SETTINGS_<NAME>` default in `_initialize-configuration`, following the existing pattern `SETTINGS_X=${REMOTE_SCRCPY_X:-default}` so precedence (CLI > environment > default) comes for free. Add the variable to the shared-state glossary comment at the top of the file. For a 0/1 toggle, add it to the `for flag in …` loop in `_validate-configuration`; any cross-option rule goes *after* that loop, because `(( SETTINGS_X ))` on an unvalidated value aborts under `set -u`. |
| `src/cli.sh` | A `case` arm in `_parse-command-line`: valueless flags sit with `--quiet`/`--ascii`; value options join the `--host|--serial|…` arm and its `--opt=value` twin. Then the help heredoc in `_print-help`: OPTIONS (two-space indent, description aligned at column 25), CONFIGURATION (the `REMOTE_SCRCPY_*` list, and the "(toggles: 0 or 1)" list if applicable), and an EXAMPLES line if the option changes the workflow. |
| `src/completion.sh` | The option word in the `options='…'` string inside the emitted completion function. Value options that complete something need a branch like `--color`. |
| `src/build.sh` | The HEADER heredoc's BASIC USAGE block if the option is a user-facing mode. Keep the header's structure: `tests/test-maintenance.sh` asserts strings in the first 45 lines of the bundle and glossary strings in the first 90. |
| `src/transport.sh`, `src/ui.sh`, `src/main.sh` | The behaviour itself. Read the lifecycle in `remote-scrcpy()` (`src/main.sh`) first; listing and help modes must stay free of network access. |

## Tests

- `tests/test-cli-ui-review.sh`: parsing and validation cases (it sources the
  modules; helper pattern `expect_output`, subshell per case).
- `tests/test-maintenance.sh`: bundle-level checks (`--help` mentions the
  option, exit status 2 for bad values, precedence with the
  `bash -c 'source …'` idiom).
- `tests/test-completion.sh`: `complete_words --<prefix>` offers the new word.

## Documentation

- `README.md` Usage block and the paragraph on options and variables.
- `CHANGELOG.md` under `## [Unreleased]` (`### Added`), with a
  `### Compatibility` note if anything existing changes.
- `src/prerequisites.sh` only if the option affects setup or troubleshooting.

## Finish

Rebuild and run the suites ([`testing.md`](testing.md)), and commit the
regenerated `remote-scrcpy.sh` with the `src/` change. The rules on example
values and on the bundle are in [`CONTRIBUTING.md`](CONTRIBUTING.md).
