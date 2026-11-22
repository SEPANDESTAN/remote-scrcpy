---
name: build-and-test
description: Rebuild remote-scrcpy.sh from src/ and run the checks CI runs - the fast suites, the bundle comparison and, where possible, the integration suite.
---

# Build and test

Use this after any change under `src/`, `tests/` or to `install.sh`, and
before every commit. The commands and what each suite covers are in
[`docs/testing.md`](../../../docs/testing.md); the rules they enforce
(generated bundle, never a real host, suites deaf to the environment) are in
[`docs/CONTRIBUTING.md`](../../../docs/CONTRIBUTING.md). Rebuild first.
