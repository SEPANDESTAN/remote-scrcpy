---
name: build-and-test
description: Rebuild remote-scrcpy.sh from src/ and run every check the CI runs, with the expected results and the environment pitfall that makes the suites fail or open a real SSH connection.
---

# Build and test

Use this after any change under `src/` or `tests/`, and before every commit.

## 1. Clear your launcher configuration

The suites inherit the environment. An exported `REMOTE_SCRCPY_HOST` makes
the maintenance suite open a real `ssh` connection to that host, and any
exported `REMOTE_SCRCPY_*` value can fail assertions (issue #4).

```bash
unset "${!REMOTE_SCRCPY_@}"
```

## 2. Rebuild the bundle

```bash
bash src/build.sh
```

This regenerates `remote-scrcpy.sh` at the repository root from the nine
modules in `src/` in the order core, cli, ssh-config, presentation, ui,
transport, prerequisites, completion, main, and runs `bash -n` on the result.
The bundle is committed; CI rebuilds it and fails on any difference. Two of
the four suites test the bundle, two source the modules, so skipping this
step tests stale code.

## 3. Run the checks

```bash
bash -n remote-scrcpy.sh
bash src/build.sh /tmp/rebuilt.sh && diff -u /tmp/rebuilt.sh remote-scrcpy.sh
bash tests/test-maintenance.sh
bash tests/test-completion.sh
bash tests/test-cli-ui-review.sh
bash tests/test-ssh-config.sh
```

Expected last lines:

```
Maintenance checks: 31 passed.
Completion checks: 10 passed.
CLI/menu review checks: 23 passed, 0 failed.
SSH config discovery checks passed.
```

Counts grow when tests are added; they never shrink without a reason stated
in the commit body. The `diff` must print nothing.

## 4. Know what is not tested

`src/transport.sh` has no coverage in these suites (issue #3). If you changed
it, say so in the commit body and, where possible, run the integration suite
(root and `sshd` required):

```bash
sudo REAL_ADB="$(command -v adb)" python3 tests/test_launcher_integration.py -v
```

Never exercise transport changes by running the launcher against a real host
from a development session. Use fake `ssh`/`adb`/`scrcpy` programs on `PATH`
(pattern in `tests/test-completion.sh`, recipe in `docs/testing.md`).

## 5. Optional static analysis

```bash
shellcheck -s bash remote-scrcpy.sh src/*.sh tests/*.sh
```

Known false positives are listed in `docs/testing.md`. Anything else is a
real finding.
