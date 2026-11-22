---
name: build-and-test
description: Rebuild remote-scrcpy.sh from src/ and run the fast checks CI runs, with the expected results, and see how to run the integration suite CI also runs.
---

# Build and test

Use this after any change under `src/` or `tests/`, and before every commit.

## 1. Rebuild the bundle

```bash
bash src/build.sh
```

This regenerates `remote-scrcpy.sh` at the repository root from the nine
modules in `src/` in the order core, cli, ssh-config, presentation, ui,
transport, prerequisites, completion, main, and runs `bash -n` on the result.
The bundle is committed; CI rebuilds it and fails on any difference. Two of
the four suites test the bundle, two source the modules, so skipping this
step tests stale code.

## 2. Run the checks

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
Maintenance checks: 41 passed.
Completion checks: 32 passed.
CLI/menu review checks: 28 passed, 0 failed.
SSH config discovery checks passed.
```

Counts grow when tests are added; they never shrink without a reason stated
in the commit body. The `diff` must print nothing.

## 3. Know what is not tested

`src/transport.sh` has no coverage in these suites. The integration suite
covers it and CI runs that on every pull request. If you changed the
transport, say so in the commit body and run it yourself first where you can
(root and `sshd` required; `docs/testing.md` has a rootless container recipe):

```bash
sudo REAL_ADB="$(command -v adb)" python3 tests/test_launcher_integration.py -v
```

Never exercise transport changes by running the launcher against a real host
from a development session. Use fake `ssh`/`adb`/`scrcpy` programs on `PATH`
(pattern in `tests/test-completion.sh`, recipe in `docs/testing.md`).

## 4. Optional static analysis

```bash
shellcheck -s bash remote-scrcpy.sh src/*.sh tests/*.sh
```

Known false positives are listed in `docs/testing.md`. Anything else is a
real finding.
