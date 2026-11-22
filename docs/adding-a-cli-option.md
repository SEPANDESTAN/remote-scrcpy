# Adding a command-line option or environment variable

The launcher has no option table; each option is registered by hand in
several places. Missing one produces a flag that works but is invisible to
help or completion, or a CI failure. Work through every row.

## Code (`src/`)

| File | What to add |
|---|---|
| `src/core.sh` | A `SETTINGS_<NAME>` default in `_initialize-configuration`, following the existing pattern `SETTINGS_X=${REMOTE_SCRCPY_X:-default}` so precedence (CLI > environment > default) comes for free. Add the variable to the shared-state glossary comment at the top of the file. For a 0/1 toggle, add it to the `for flag in …` loop in `_validate-configuration`; any cross-option rule goes *after* that loop, because `(( SETTINGS_X ))` on an unvalidated value aborts under `set -u`. |
| `src/cli.sh` | A `case` arm in `_parse-command-line`: valueless flags sit with `--quiet`/`--ascii`; value options join the `--host\|--serial\|…` arm and its `--opt=value` twin. An option that makes the run do something else than connect (a mode, like `--list-hosts`) sets it through `_select-operation`, joins the message there and the `case` after the loop that says what the mode refuses, and joins the `modes` list in `tests/test-cli-ui-review.sh`. Then the help heredoc in `_print-help`: OPTIONS (the letter at column 3 or four spaces in its place, the long name at column 7, the description at column 29, no line over 80 characters), CONFIGURATION (the `REMOTE_SCRCPY_*` list, and the "(toggles: 0 or 1)" list if applicable), and an EXAMPLES line if the option changes the workflow. |
| `src/completion.sh` | The option word in the `options='…'` string inside the emitted completion function. An option that takes a value must also join the `--host\|--serial\|…` arm of the word loop in `_remote-scrcpy-complete-words`, which skips the value; left out, the value is counted as a positional, taken for the host, and a device lookup goes there. If something can complete the value, add an arm to the `case $previous` block and one for the `--option=` form, like `--color`; if nothing can, add it to the arm that returns without candidates, like `--adb-port`. |
| `src/build.sh` | The HEADER heredoc's BASIC USAGE block if the option is a user-facing mode. Keep the header's structure: `tests/test-maintenance.sh` asserts strings in the first 45 lines of the bundle and glossary strings in the first 90. |
| `src/transport.sh`, `src/ui.sh`, `src/main.sh` | The behaviour itself. Read the lifecycle in `remote-scrcpy()` (`src/main.sh`) first; listing and help modes must stay free of network access. |

## Tests

- `tests/test-cli-ui-review.sh`: parsing and validation cases (it sources the
  modules; helper pattern `expect_output`, subshell per case).
- `tests/test-maintenance.sh`: bundle-level checks (`--help` mentions the
  option, exit status 2 for bad values, precedence with the
  `bash -c 'source …'` idiom).
- `tests/test-completion.sh`: `complete_words --<prefix>` offers the new word.

## A short form

Only for an option that is typed often. The letter joins the option's
`case` pattern in `_parse-command-line` (`-l|--list-devices`), its line in
the help's OPTIONS block (`-l, --list-devices`), the `options` word list of
the completion, the header line in `src/build.sh` and the table in the
README. Short options are not bundled and take no attached value.

In the tests it joins three lists: `short_forms` in
`tests/test-cli-ui-review.sh`, which checks that the letter sets what its
long name sets and nothing else; the `pair` list in
`tests/test-maintenance.sh`, which checks the help; and `all_options` in
`tests/test-completion.sh`. `tests/test-maintenance.sh` also compares the
bundle's output for the letter and the long name, but only for an option
that ends the run without connecting, like `--help` or `--prerequisites`.

Before choosing a letter, look at what it means to scrcpy: someone who
forgets the `--` gets the launcher's meaning.

## Documentation

- `README.md` Usage block and the paragraph on options and variables.
- `CHANGELOG.md` under `## [Unreleased]` (`### Added`), with a
  `### Compatibility` note if anything existing changes.
- `src/prerequisites.sh` only if the option affects setup or troubleshooting.

## Finish

Rebuild and run the suites ([`testing.md`](testing.md)), and commit the
regenerated `remote-scrcpy.sh` with the `src/` change. The rules on example
values and on the bundle are in [`CONTRIBUTING.md`](CONTRIBUTING.md).
