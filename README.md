# remote-scrcpy

A single [Bash](https://www.gnu.org/software/bash/) executable for viewing and controlling Android phones attached by USB to a different computer. [scrcpy](https://github.com/Genymobile/scrcpy) runs on the viewer, using [SSH](https://www.openssh.com/) forwards to reach the remote computer's existing authorized [ADB](https://developer.android.com/tools/releases/platform-tools) connection. **No terminal UI executable, downloader, package installer, or self-extracting payload is required.**

## Install

Only `remote-scrcpy.sh` is needed at runtime — everything under `src/` is for development.

The examples below install into `$HOME/.local/bin`, which is on `PATH` by default in most modern distributions. Any directory on your `PATH` works equally well; common alternatives include `/usr/local/bin` (needs `sudo`) or a project-specific `bin/` directory you source into `PATH` yourself. The file name is up to you: it is referenced here as `remote-scrcpy`, but if you install it under a different name, re-register Bash completion with `complete -F _complete-remote-scrcpy your-command-name`.

### Option 1 — download the single-file script

```bash
install_dir="$HOME/.local/bin"            # or /usr/local/bin, or anywhere on PATH
mkdir -p "$install_dir"
curl -fsSL -o "$install_dir/remote-scrcpy" \
    https://raw.githubusercontent.com/SEPANDESTAN/remote-scrcpy/main/remote-scrcpy.sh
chmod +x "$install_dir/remote-scrcpy"
```

### Option 2 — clone and install from a checkout

```bash
git clone https://github.com/SEPANDESTAN/remote-scrcpy.git
install -m 755 remote-scrcpy/remote-scrcpy.sh "$HOME/.local/bin/remote-scrcpy"
```

Ensure the chosen install directory is on your `PATH`, then verify:

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

The viewer requires Bash 4.4+, an [OpenSSH](https://www.openssh.com/) client, an accessible `adb`, and `scrcpy`. `awk`, `mktemp`, `rm`, and `sleep` are standard operating-system utilities used by this script. The remote needs an SSH server with local TCP forwarding enabled, `adb`, and authorized USB debugging. The viewing computer must have a graphical session. If your scrcpy installation ships adb, it must still be accessible as an executable, because the launcher calls it directly. See `--prerequisites` for checks.

## Interactive flow and customization

Host and device selection use numbered prompts, exact serials and an optional manual-host entry. Offline/unauthorized devices are displayed but not selectable. `r` refreshes the remote device list; `q` cancels. Color and decoration are intentionally modest. Use `--ascii`, `--color=never`, or [`NO_COLOR=1`](https://no-color.org/) to customize presentation.

Supply any part of the selection through `[HOST [SERIAL]]`, `--host`, `--serial`, or the corresponding `REMOTE_SCRCPY_*` variables. The precedence is explicit command-line value, environment variable, then built-in default. `--` forwards additional arguments to scrcpy (except conflicting transport/device flags). Use `--verbose` for connection diagnostics and `--non-interactive` for scripts where both host and device are supplied. Full options and environment variables are documented by `--help`.

## Bash completion

```bash
source <(remote-scrcpy --completion bash)
```

Add that line to `~/.bashrc` for persistent completion. **Host aliases come from the local SSH configuration, while phone serials are queried live from the selected SSH host by default.** For example, type `remote-scrcpy r<Tab>` to complete a host or `remote-scrcpy remote-host D<Tab>` to look up online Android serials attached to `remote-host`. Both `--host` and `--serial` accept completion, including `--host=` and `--serial=` forms. Only devices in `device` state are offered.

Remote completion invokes a noninteractive `ssh HOST 'adb devices -l'` equivalent. It uses SSH `BatchMode`, connection/keepalive limits, and (where installed) an optional `timeout` wrapper (default 6 seconds). This does **not** use the script’s SSH tunnel or start scrcpy, but ordinary ADB may start its local daemon on the remote machine while listing devices. The first SSH connection should be established normally beforehand if a host-key prompt or password is required; completion itself will not prompt. Set `REMOTE_SCRCPY_COMPLETE_DEVICES=0` to disable remote queries or `REMOTE_SCRCPY_COMPLETION_TIMEOUT=8` to adjust the optional time limit. `REMOTE_SCRCPY_SSH_CONFIG` and `REMOTE_SCRCPY_REMOTE_ADB` are respected; corresponding `--ssh-config` and `--remote-adb` arguments work too.

Completion output is ordinary Bash, with no special runtime UI. If the executable is installed under a different name, register that command with `complete -F _complete-remote-scrcpy your-command-name`.

## Internal naming

Internal shell variables are grouped by prefix. These are **internal**, not a public API; documented `REMOTE_SCRCPY_*` environment variables are the supported interface.

| Internal group | Purpose | Example |
|---|---|---|
| `SETTINGS_*` | Parsed options and environment defaults | `SETTINGS_SSH_HOST`, `SETTINGS_DEVICE_SERIAL` |
| `SESSION_*` | Resources owned by the active connection | `SESSION_SSH_CONTROL_SOCKET`, `SESSION_LOCAL_ADB_TUNNEL_PORT` |
| `DISCOVERED_DEVICE_*` | Parallel arrays of remote device metadata | `DISCOVERED_DEVICE_SERIALS` |
| `DISPLAY_*` | Optional terminal escape codes and symbols | `DISPLAY_COLOR_WARNING` |
| `CLI_*` | Tracks explicitly supplied arguments | `CLI_HOST_EXPLICIT` |
| `INPUT_RESPONSE` | Last answer received from the plain-text picker | `INPUT_RESPONSE` |
| `APPLICATION_VERSION` | Program version | — |

The long file-level header on the generated executable explains setup, usage, help, and prerequisites. `src/core.sh` contains the shared-state glossary; `src/transport.sh` documents which connection resources must be cleaned up. Source changes should be made in the individual modules, followed by `bash src/build.sh` and the regressions below.

## Architecture for maintainers

`remote-scrcpy.sh` is built from the source modules under `src/` using `bash src/build.sh`. The bundled script at the repo root is the only file necessary at runtime. Source modules are concatenated in this order: `core.sh`, `cli.sh`, `ssh-config.sh`, `presentation.sh`, `ui.sh`, `transport.sh`, `prerequisites.sh`, `completion.sh`, `main.sh` (all under `src/`).

- `core.sh`: one-time state initialization, reusable validation/logging, prerequisite executable resolution.
- `cli.sh`: parsing, help and precedence; no network access.
- `ssh-config.sh`: static alias discovery; never interpret executable SSH config expressions.
- `presentation.sh`: plain TTY formatting; stdout data remains unstyled.
- `ui.sh`: numbered host/device menus and device listing, with remote transport abstracted behind an internal adb helper.
- `transport.sh`: SSH master, forward allocation, ADB protocol compatibility, scrcpy lifecycle and cleanup.
- `prerequisites.sh`: detailed static instructions, including marked placeholders for future site-specific setup.
- `completion.sh`: writes an opt-in completion function to stdout; no installation side effects.
- `main.sh`: `remote-scrcpy` is the single public function; it orchestrates lifecycle and traps.

**Function conventions:** public entry point is `remote-scrcpy` (two words); internal helpers start with `_` and use explanatory kebab-case names. Functions should have short purpose, arguments/state, side-effect, and failure comments. Internal globals use named namespaces: `SETTINGS_*` (resolved configuration), `DISCOVERED_DEVICE_*` (parallel device arrays), `DISPLAY_*` (terminal styles), `CLI_*` (explicit CLI-argument flags), `INPUT_RESPONSE` (last prompt), and `SESSION_*` (connection resources owned by transport). This keeps these internal values distinct from the public `REMOTE_SCRCPY_*` environment-variable interface. Prefer explicit `local` inside helpers. Do not introduce `eval`, execute SSH config, or launch any GUI/tunnel during completion; remote SSH device discovery is intentional and bounded. Avoid adding dependency bootstrap code to the normal execution path.

**Lifecycle invariant:** install EXIT/signal cleanup before opening SSH; use private control socket/port leases; never terminate a shared remote ADB server. Use `tcp:PORT` only when starting the remote *local* ADB daemon, and `tcp:127.0.0.1:PORT` for a remote server accessed through an SSH tunnel. A protocol check prevents automatically restarting a mismatched shared server. Scrcpy device and tunnel flags are owned by the launcher.

**Port reservation:** local SSH listeners reserve chosen ports; the remote port is atomically allocated through ADB `forward tcp:0`. Cleanup checks the original session's device and unique reservation before removing an unclaimed forwarding record. Never hardcode one shared mirroring port when supporting simultaneous sessions.

## Remote server and phone preparation

Use `remote-scrcpy --prerequisites` for the current generic checklist. That command is designed for later site-specific instructions, once details are provided. Do not invent platform-specific commands; add exact steps for the remote operating system, Android models, USB permissions and SSH policy once verified.

> **TODO** — the site-specific portion of the prerequisites is intentionally still a placeholder. Expansion is tracked in [issue #1](https://github.com/SEPANDESTAN/remote-scrcpy/issues/1), which contains a questionnaire covering remote OS, USB permissions, phone models, SSH policy, auth, and recovery. Fill those in before turning the `[TODO]` markers in `src/prerequisites.sh` into prescriptive instructions.

## Tests and limits

Run `bash -n remote-scrcpy.sh`, `bash tests/test-maintenance.sh`, `bash tests/test-completion.sh`, `bash tests/test-cli-ui-review.sh`, and `bash tests/test-ssh-config.sh`. The source also retains an optional integration fixture for real OpenSSH/ADB with simulated devices; that *development-only* fixture uses Python and is **not** required to install, build, or run the launcher. Physical phone mirroring still needs testing on the viewer.

Supported expectations are intentionally explicit: this Bash implementation is verified primarily on Linux. It needs Bash 4.4+ and OpenSSH Unix-style control sockets. Do not assume every operating system/architecture is verified simply because the script contains no native embedded payload.
