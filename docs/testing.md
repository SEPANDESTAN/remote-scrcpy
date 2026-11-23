# Testing

## The fast suites (run in CI)

```bash
bash -n remote-scrcpy.sh
bash tests/test-maintenance.sh
bash tests/test-completion.sh
bash tests/test-cli-ui-review.sh
bash tests/test-ssh-config.sh
bash tests/test-install.sh
```

They need no network, no phone and no root. A suite that fails exits
non-zero, and every check says what failed. `test-cli-ui-review.sh` runs
all its checks and gives the number of failures in its last line; the others
stop at the first failure. A suite that passes ends with a line saying so,
most of them with the number of checks. That number grows when tests are
added; a check is not removed without the reason in the commit body.

CI (`.github/workflows/test.yml`) additionally rebuilds the bundle and diffs
it against the committed `remote-scrcpy.sh`; a stale bundle fails the build.
Run the same check locally:

```bash
bash src/build.sh /tmp/rebuilt.sh && diff -u /tmp/rebuilt.sh remote-scrcpy.sh
```

### Which code each suite touches

| Suite | Runs against | Covers |
|---|---|---|
| `test-maintenance.sh` | the bundle | that every module under `src/` is in the bundle, `src/build.sh` usage and option errors, version string, help/prerequisites/completion output, that the help, version, prerequisites, completion and host-listing modes write no terminal escape to standard output with color forced on, that the launcher adds no locale warning of its own, bundle header text, exit codes for bad options, precedence, host listing, emitted completion function, regression greps (no `gum`, `--ui=`, `base64 --decode`, no `RS_*`) |
| `test-completion.sh` | the bundle | alias and serial completion with a fake `ssh` on `PATH`, fed words split the way an interactive Bash splits them (at `=`, `@` and `:`); `--host=`/`--serial=` forms, file names after `--ssh-config=`, `--adb=` and `--remote-adb=`, aliases after `user@`, serials with a colon, that a serial with anything but plain characters in it is not offered, which host a lookup contacts, that a lookup reads nothing from its input, positions with `REMOTE_SCRCPY_HOST` exported, `REMOTE_SCRCPY_COMPLETE_DEVICES=0` |
| `test-cli-ui-review.sh` | sources `src/core.sh`, `cli.sh`, `presentation.sh`, `ui.sh` | argument parsing, validation errors, numbered menus and exact-serial entry with stubbed prompts, what the display sanitizer replaces and leaves alone, whether each color mode colors and which marks are used, with and without `NO_COLOR`, on a terminal and off one (the suite answers for the launcher's terminal test, `_stderr-is-terminal`) |
| `test-ssh-config.sh` | sources `src/ssh-config.sh` | `Host`/`Include` discovery fixtures, quoting, negation, wildcards, recursion |
| `test-install.sh` | `install.sh` and the bundle | the installer in a scratch `HOME` with a `PATH` of chosen tools and a fake `curl`: usage errors, which stream gets what, install from a checkout without network (by path and by bare name), `--dir` (relative, with a space, with `~` after `=`), `--with-tab-completion` (one line, once, that registers the completion without `PATH`; an existing line for another place is left alone), the download address for `main` and for `--version` (a bare release number, a tag, a branch), the short forms and the older names `--ref` and `--completion`, that a failed, unparsable or foreign download installs nothing and leaves the old launcher in place, and that an installer cut anywhere in its last line installs nothing. The real download is not exercised |

Some suites run the bundle and others source the modules, so **always
rebuild before testing** a `src/` change, or the former test stale code.

### Not covered

`src/transport.sh` (SSH master, port leases, ADB protocol probe, remote
start-server, scrcpy launch, signal escalation, cleanup) has no coverage in
the fast suites, and neither do the long-option branch of
`_validate-scrcpy-arguments` (its short-flag branch is covered) or the
device-state filter in `src/ui.sh`.
The 2026-11-06 review proved it by mutation (table in
`review-2026-11-06.md`). The launcher's own test for a terminal on standard
error is one line that the CLI suite replaces; the integration suite runs
it for real, on a pseudo-terminal. The integration suite below is what
covers the transport, and CI runs it. Of the seven mutations listed in issue #3 it
catches six when they are planted one at a time, and each half of the
socket-form mutation alone. The seventh, removing the hex check on the
length of the version reply, is no longer a defect a test can see: the
conversion behind the check refuses the same input with the same message. A
module dropped from the build list is caught by the maintenance suite,
whichever module it is. Each check the protocol probe makes on the content
of a reply has a test of its own, including the hex check on the version
payload and its bound of eight digits. Numbers that come from the remote,
the two hex fields of that reply and the port the server reports for a
reservation, are converted with `printf`, which evaluates nothing, behind
their checks; a reply crafted to run a command is stopped by either, and a
test for each fails only when both are gone. The probe's read timeouts are not
exercised. The suite also covers the device menu offering only devices that
are ready, that control characters in the model name a phone reports are
replaced in the device list and in the menu, and what reaches which stream: with color forced on, the device
list and a connecting run put no terminal escape on standard output, the
host menu puts nothing there at all, and the automatic color mode follows
a pseudo-terminal on standard error and on no other stream.

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

Every fast suite also closes its standard input, with `exec < /dev/null` as
its next command; the maintenance suite checks that line too. It matters to
a suite that starts programs in an emptied environment, and it is required
of all five so that nobody has to work out which ones those are. The reason
is a startup rule of Bash: started with `-c`, without an inherited `SHLVL`,
and with a socket on standard input, it takes itself for a remote shell
([bash(1), INVOCATION](https://man7.org/linux/man-pages/man1/bash.1.html)) and
reads `~/.bashrc`, which commonly sources the system-wide file too (Fedora's
does, and some builds of Bash read that file themselves). An
agent's command runner and a remote command both provide such a socket,
some of the time. The first version of `test-install.sh` did this with a
`PATH` holding only the installer's tools and without `HOME`, so that the
developer's own file was the one read: a command-not-found handler defined
by the system startup files called a missing program from inside
itself, and the forks that followed exhausted the machine's memory. Give
child shells a sandbox `HOME` as well, and run a script file with
`bash --norc` in preference to `bash -c`.

Some checks in the maintenance, CLI and install suites need a locale in
which a pattern range misbehaves, or they could not fail: one where `[0-9]`
also matches the digits of other scripts (`en_US.UTF-8` with
[glibc](https://www.gnu.org/software/libc/) is one), and for the installer
one where `[a-z]` does not match `i` (`tr_TR.UTF-8`). Each suite tries a
short list of locale names with the range itself. Where none is installed
or none behaves so, it prints a note on standard error, passes without
those checks, and counts that many fewer. Two more checks, on the warning
Bash prints for a locale that is not installed, are skipped the same way
where the C library accepts any locale name
([musl](https://musl.libc.org/) does). And two checks that the display
sanitizer gives the same result in every locale need the two kinds of
locale that would show a difference: an eight-bit one (`en_US.ISO-8859-1`
and two more are tried) and one that reads the bytes 0xC2 0x9D as a single
letter (`zh_CN.GBK` and one more). CI generates a locale of each kind
named here and fails if one of them does not behave so, which is what makes a green run mean
that these checks ran. The check that no such range is written in `src/` or
`install.sh` runs everywhere.

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
suites; that job fails if the suite skips. If you changed
`src/transport.sh`, say so in the commit body.

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

Run this suite once at a time on a machine, or give each run a container
of its own. On Debian and Ubuntu, which CI and the container above use,
`sshd` refuses connections without its directory `/run/sshd`. The suite
creates that directory when it is missing and removes it again at the end,
so as to leave the machine as it found it. A second run that starts while
the first is going finds the directory there and does not count it as its
own; when the first run finishes and removes it, the second fails most of
its tests with `Connection reset by peer`. A single run is not affected,
and CI runs it once, on a runner of its own.

## Static analysis

```bash
shellcheck -s bash remote-scrcpy.sh install.sh src/*.sh tests/*.sh
```

[shellcheck](https://github.com/koalaman/shellcheck) is not in CI. Version
0.11.0 reports no real defect on the bundle, the installer, the modules and
the tests. Expected false positives: SC1007 (deliberate `A= B=` chained
empty assignments), SC1003 (quoted backslash), SC2088 (literal `'~/'` case
pattern), SC2030/SC2031 (`LC_ALL` export scoped to a subshell on purpose),
SC2034 (cross-module variables when a module is checked alone), SC2015 (an
`A && B || die` chain meant as written), SC1090/SC1091/SC2329 in
the tests (dynamic `source`, helpers invoked indirectly). Fix anything else,
or justify it with a `# shellcheck disable=` comment that says why. Static
binaries: https://github.com/koalaman/shellcheck/releases
