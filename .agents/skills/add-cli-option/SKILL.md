---
name: add-cli-option
description: Checklist of every file and text block that must change when adding a command-line option or REMOTE_SCRCPY_* variable to remote-scrcpy, including the hidden couplings in the tests.
---

# Add a CLI option or environment variable

The checklist is [`docs/adding-a-cli-option.md`](../../../docs/adding-a-cli-option.md).
Read it and work through every row: the launcher has no option table, so an
option missed in one place works but is invisible to help or completion, or
fails CI.
