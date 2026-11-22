# Testing

## The fast suites (run in CI)

```bash
bash -n remote-scrcpy.sh
bash tests/test-maintenance.sh       # expects: Maintenance checks: 50 passed.
bash tests/test-completion.sh        # expects: Completion checks: 32 passed.
bash tests/test-cli-ui-review.sh     # expects: CLI/menu review checks: 31 passed, 0 failed.
bash tests/test-ssh-config.sh        # expects: SSH config discovery checks passed.
```

CI (`.github/workflows/test.yml`) additionally rebuilds the bundle and diffs
it against the committed `remote-scrcpy.sh`; a stale bundle fails the build.
Run the same check locally:

```bash
bash src/build.sh /tmp/rebuilt.sh && diff -u /tmp/rebuilt.sh remote-scrcpy.sh
```

### Which code each suite touches

| Suite | Runs against | Covers |
|---|---|---|
| `test-maintenance.sh` | the bundle | version string, help/prerequisites/completion output, bundle header text, exit codes for bad options, precedence, host listing, emitted completion function, regression greps (no `gum`, `--ui=`, `base64 --decode`, no `RS_*`) |
| `test-completion.sh` | the bundle | alias and serial completion with a fake `ssh` on `PATH`, fed words split the way an interactive Bash splits them (at `=`, `@` and `:`); `--host=`/`--serial=` forms, serials with a colon, which host a lookup contacts, that a lookup reads nothing from its input, positions with `REMOTE_SCRCPY_HOST` exported, `REMOTE_SCRCPY_COMPLETE_DEVICES=0` |
| `test-cli-ui-review.sh` | sources `src/core.sh`, `cli.sh`, `presentation.sh`, `ui.sh` | argument parsing, validation errors, numbered menus and exact-serial entry with stubbed prompts, whether the explicit color modes color with and without `NO_COLOR` |
| `test-ssh-config.sh` | sources `src/ssh-config.sh` | `Host`/`Include` discovery fixtures, quoting, negation, wildcards, recursion |

Two suites run the bundle and two source the modules, so **always rebuild
before testing** a `src/` change, or half the suites test stale code.

### Not covered

`src/transport.sh` (SSH master, port leases, ADB protocol probe, remote
start-server, scrcpy launch, signal escalation, cleanup) has no coverage in
the fast suites, and neither do the long-option branch of
`_validate-scrcpy-arguments` (its short-flag branch is covered), the
device-state filter in `src/ui.sh`, the `auto` color mode on a terminal (the suites have
none; issue #27), or the module list in `src/build.sh`.
The 2026-11-06 review proved it by mutation (table in
`review-2026-11-06.md`). The integration suite below is what covers the
transport, and CI runs it. It catches each of the seven mutations listed in
issue #3 when they are planted one at a time, and each half of the
socket-form mutation alone. Dropping a module from the build list is caught
only where a test happens to need that module. Each check the protocol probe
makes on the content of a reply has a test of its own, including the hex
check on the version payload: that payload comes from the remote and is
converted with shell arithmetic, and the check is what keeps anything but
hex digits away from the conversion. The probe's read timeouts are not
exercised. The suite also covers the device menu offering only devices that
are ready.

### Environment

Every fast suite begins by clearing the launcher's public environment
(`REMOTE_SCRCPY_*`, the fallbacks `ADB`, `REMOTE_ADB`, `ADB_PORT`, `SCRCPY`,
and `NO_COLOR`). The integration fixture drops the same variables from the
environment it hands to the launcher, except `SCRCPY`, which it points at its
stand-in. An exported `REMOTE_SCRCPY_HOST`, which is how the
launcher is meant to be configured, therefore cannot make a test contact
that host. The maintenance suite fails unless that line is the first command
after `set -euo pipefail` in every `tests/test-*.sh`, so a new suite has to
start with it too.

## The integration suite

`tests/test_launcher_integration.py` runs the real launcher against a real
OpenSSH server and a real `adb` binary, with a simulated ADB server
(`tests/native_adb_fixture.py`) and a simulated scrcpy (`tests/fake_scrcpy.py`).
It is the only end-to-end test of `src/transport.sh`.

Requirements: root (it starts an isolated `sshd` on a loopback port with
temporary keys), `sshd`, `ssh-keygen`, Python 3, a real `adb`. No existing
credentials, phones or servers are used.

```bash
sudo REAL_ADB="$(command -v adb)" python3 tests/test_launcher_integration.py -v
```

Without root or `sshd` it skips itself. CI runs it on every pull request and
on every push to `main` in a job of its own, `integration`, next to the fast
suites; that job fails if the suite skips.

Without root on your machine, a rootless [Podman](https://podman.io/)
container gives it a root of its own and keeps everything on the container's
loopback interface:

```bash
podman run --rm --security-opt label=disable -v "$PWD":/repo:ro \
    docker.io/library/ubuntu:24.04 bash -c '
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq && apt-get install -y -qq openssh-server adb python3
        cd /repo && REAL_ADB="$(command -v adb)" python3 -B tests/test_launcher_integration.py -v'
```

## Writing a hermetic transport test

The project decided against building a full suite this way (see the
2026-11-22 entry in `decisions.md`): the integration suite covers the
transport. The recipe stays as the way to exercise a single transport
function with fake programs when no `sshd` or root is at hand.

No refactoring is required. Source `src/core.sh`, `presentation.sh`,
`ui.sh`, `transport.sh` and `main.sh` (its entry point is guarded by
`BASH_SOURCE == $0`), run each case in a `( … )` subshell because
`_exit-with-error` calls `exit`, set the `SETTINGS_*`/`SESSION_*` globals
directly, and put fake programs first on `PATH`:

- `ssh`: `-fMNT … -- host` creates the `-S` socket path and exits 0; `-O check`
  exits 0; `-O forward -L 127.0.0.1:C:127.0.0.1:R` starts a loopback relay
  from `C` to the fake ADB port; `-O exit` stops it. Log every argv.
- `adb`: prints `Android Debug Bridge version 1.0.41`; canned `devices -l`
  output including `\r` endings, `no permissions (…)`, `model:A_B`, a
  `host:5555` serial; `forward tcp:0 TOKEN` prints a port; `forward --list`
  prints rows. Log argv and `ADB_SERVER_SOCKET`.
- `scrcpy`: logs argv, environment and process group; sleeps or exits with a
  chosen status; optionally ignores INT and TERM to exercise escalation.
- Fake ADB server: reuse `NativeADBServer` from `tests/native_adb_fixture.py`
  on a loopback port. `_read-adb-server-protocol` only needs
  `SESSION_LOCAL_ADB_TUNNEL_PORT`, so no `sshd` is needed.

Functions already callable in isolation: `_quote-remote-shell-argument`,
`_validate-scrcpy-arguments`, `_read-adb-server-protocol`,
`_probe-adb-server`, `_create-local-ssh-forward`,
`_reserve-device-forwarding-port`, `_launch-scrcpy`, `_stop-scrcpy-process`,
`_cleanup-remote-connection`, `_load-remote-device-list`,
`_validate-selected-device`. Override `_probe-adb-server` by redefining it
when a case does not need a server.

Use the mutation table in `review-2026-11-06.md` as the acceptance list: a
transport suite is good enough when every row that reads "none" is caught.

## Static analysis

shellcheck is not in CI. Running 0.11.0 on the bundle, the modules and the
tests reports no real defect. Expected false positives: SC1007 (deliberate
`A= B=` chained empty assignments), SC1003 (quoted backslash), SC2088
(literal `'~/'` case pattern), SC2030/SC2031 (`LC_ALL` export scoped to a
subshell on purpose), SC2034 (cross-module variables when a module is
checked alone), SC1090/SC1091/SC2329 in the tests (dynamic `source`, helpers
invoked indirectly). Static binaries:
https://github.com/koalaman/shellcheck/releases
