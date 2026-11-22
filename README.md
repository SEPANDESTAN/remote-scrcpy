# remote-scrcpy

A single [Bash](https://www.gnu.org/software/bash/) executable for viewing and controlling Android phones attached by USB to a different computer. [scrcpy](https://github.com/Genymobile/scrcpy) runs on the viewer, using [SSH](https://www.openssh.com/) forwards to reach the remote computer's existing authorized [ADB](https://developer.android.com/tools/releases/platform-tools) connection. **No terminal UI executable, downloader, package installer, or self-extracting payload is required.**

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/SEPANDESTAN/remote-scrcpy/main/install.sh | bash
```

`install.sh` downloads one file with [curl](https://curl.se/), checks that it runs, and puts it at `~/.local/bin/remote-scrcpy`. It never uses `sudo` and installs nothing else: `ssh`, `adb` and `scrcpy` are yours to provide, and it tells you which of them it did not find. Options go after `bash -s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/SEPANDESTAN/remote-scrcpy/main/install.sh | bash -s -- --with-tab-completion
```

| Option | Short | Effect |
|---|---|---|
| `--with-tab-completion` | `-c` | also add Bash completion to `~/.bashrc`: one marked line, added once; an existing completion line is left alone |
| `--dir DIR` | `-d` | install into `DIR` instead of `~/.local/bin` |
| `--version VERSION` | `-v` | download a release, such as `3.1.0` or `v3.1.0`, or a branch, instead of `main` |

So `bash -s -- -c -d ~/bin` adds completion and installs into `~/bin`. The names of 3.1.0, `--completion` and `--ref`, still work.

From a checkout, `bash install.sh` installs that checkout's `remote-scrcpy.sh` and uses no network.

To install by hand instead: only `remote-scrcpy.sh` is needed at runtime, and everything under `src/` is for development. Put it in any directory on your `PATH` under any name:

```bash
mkdir -p "$HOME/.local/bin"
curl -fsSL -o "$HOME/.local/bin/remote-scrcpy" \
    https://raw.githubusercontent.com/SEPANDESTAN/remote-scrcpy/main/remote-scrcpy.sh
chmod +x "$HOME/.local/bin/remote-scrcpy"
```

Then verify:

```bash
remote-scrcpy --version
remote-scrcpy --prerequisites
```

## Usage

```bash
remote-scrcpy --help
remote-scrcpy                         # choose host and device
remote-scrcpy remote-host               # choose device on host
remote-scrcpy remote-host SERIAL        # connect directly
remote-scrcpy --list-devices remote-host
```

The options used every day also have a one-letter form:

| Option | Short | What it does |
|---|---|---|
| `--list-devices HOST` | `-l` | list the phones attached to `HOST` |
| `--list-hosts` | `-L` | list the host aliases in your SSH config |
| `--prerequisites` | `-p` | print the setup checklist |
| `--quiet` | `-q` | hide the banner and progress lines |
| `--non-interactive` | `-n` | never prompt |
| `--verbose` | `-V` | show SSH and transport details |
| `--version` | `-v` | print the version |
| `--help` | `-h` | print the help |

So `remote-scrcpy -l remote-host` is `remote-scrcpy --list-devices remote-host`. A short option stands alone, one per word: `-q -l`, not `-ql`. Options for scrcpy itself go after `--` and keep scrcpy's own meaning there, which can differ from the launcher's: scrcpy's `-n` (no control) is `remote-scrcpy remote-host -- -n`, while `-n` before the `--` is the launcher's `--non-interactive`.

The viewer requires Bash 4.4+, an [OpenSSH](https://www.openssh.com/) client, an accessible `adb`, and `scrcpy`. `awk`, `cat`, `env`, `mktemp`, `rm`, and `sleep` are standard operating-system utilities used by this script. The remote needs an SSH server with local TCP forwarding enabled, `adb`, and authorized USB debugging. The viewing computer must have a graphical session. If your scrcpy installation ships adb, it must still be accessible as an executable, because the launcher calls it directly. See `--prerequisites` for checks.

## Interactive flow and customization

Host and device selection use numbered prompts, exact serials and an optional manual-host entry. Offline/unauthorized devices are displayed but not selectable. `r` refreshes the remote device list; `q` cancels. Color and decoration are intentionally modest. Use `--ascii`, `--color=never`, or [`NO_COLOR=1`](https://no-color.org/) to customize presentation.

Supply any part of the selection through `[HOST [SERIAL]]`, `--host`, `--serial`, or the corresponding `REMOTE_SCRCPY_*` variables. The precedence is explicit command-line value, environment variable, then built-in default. `--` forwards additional arguments to scrcpy (except conflicting transport/device flags). Use `--verbose` for connection diagnostics and `--non-interactive` for scripts where both host and device are supplied. Full options and environment variables are documented by `--help`.

## Bash completion

```bash
source <(remote-scrcpy --completion bash)
```

Add that line to `~/.bashrc` for persistent completion. **Host aliases come from the local SSH configuration, while phone serials are queried live from the selected SSH host by default.** For example, type `remote-scrcpy r<Tab>` to complete a host or `remote-scrcpy remote-host D<Tab>` to look up online Android serials attached to `remote-host`. Both `--host` and `--serial` accept completion, including `--host=` and `--serial=` forms. Only devices in `device` state are offered. Positions mean the same with or without `REMOTE_SCRCPY_HOST`: the first positional is the host, so with a host in the environment, complete a serial for it with `--serial <Tab>`.

Remote completion invokes a noninteractive `ssh HOST 'adb devices -l'` equivalent. It uses SSH `BatchMode`, connection/keepalive limits, and (where installed) an optional `timeout` wrapper (default 6 seconds). This does **not** use the script’s SSH tunnel or start scrcpy, but ordinary ADB may start its local daemon on the remote machine while listing devices. The first SSH connection should be established normally beforehand if a host-key prompt or password is required; completion itself will not prompt. Set `REMOTE_SCRCPY_COMPLETE_DEVICES=0` to disable remote queries or `REMOTE_SCRCPY_COMPLETION_TIMEOUT=8` to adjust the optional time limit (1 to 99 seconds; it only applies where a `timeout` program is installed). Completion always asks the remote's default ADB server: `--adb-port` and `REMOTE_SCRCPY_ADB_PORT` do not apply to it. `REMOTE_SCRCPY_SSH_CONFIG` and `REMOTE_SCRCPY_REMOTE_ADB` are respected; corresponding `--ssh-config` and `--remote-adb` arguments work too.

Completion output is ordinary Bash, with no special runtime UI. If the executable is installed under a different name, register that command with `complete -F _complete-remote-scrcpy your-command-name`.

## Developing

`remote-scrcpy.sh` is generated from the modules under `src/` and committed. Start at [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md): what you need, the first build, the rules, and where everything else is written down. AI coding agents start at [`AGENTS.md`](AGENTS.md).

## Remote server and phone preparation

Use `remote-scrcpy --prerequisites` for the current generic checklist. That command is designed for later site-specific instructions, once details are provided. Do not invent platform-specific commands; add exact steps for the remote operating system, Android models, USB permissions and SSH policy once verified.

> **TODO** — the site-specific portion of the prerequisites is intentionally still a placeholder. Expansion is tracked in [issue #1](https://github.com/SEPANDESTAN/remote-scrcpy/issues/1), which contains a questionnaire covering remote OS, USB permissions, phone models, SSH policy, auth, and recovery. Fill those in before turning the `[TODO]` markers in `src/prerequisites.sh` into prescriptive instructions.

## Limits

Supported expectations are intentionally explicit: this Bash implementation is verified primarily on Linux. It needs Bash 4.4+ built with `/dev/tcp` support (the default) and OpenSSH Unix-style control sockets; the session's socket is created under `/tmp` whatever `TMPDIR` says, because socket paths are limited in length. Do not assume every operating system/architecture is verified simply because the script contains no native embedded payload.

The tunnels are plain TCP on the loopback interface, on the viewing computer and on the remote, for as long as a session lasts. Like adb's own port 5037 they have no per-user access control, so other accounts on either machine can connect to them. Use the launcher on machines whose other users you trust.

scrcpy runs in a process group of its own so that Ctrl+C reaches the launcher first. On a terminal with `stty tostop` set, that group is stopped at scrcpy's first log line and no window appears; run `stty -tostop` first.

Besides the `REMOTE_SCRCPY_*` variables, the launcher reads four generic ones as fallbacks: `ADB`, `REMOTE_ADB`, `ADB_PORT` and `SCRCPY`. An `ADB_PORT` inherited from another tool therefore changes which remote ADB server is used; set `REMOTE_SCRCPY_ADB_PORT` to override it. Exit statuses are listed by `--help`.
