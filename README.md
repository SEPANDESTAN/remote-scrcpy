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
install -D -m 755 remote-scrcpy/remote-scrcpy.sh "$HOME/.local/bin/remote-scrcpy"   # -D creates the directory
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

## Developing

Only `remote-scrcpy.sh` is needed at runtime; it is generated from the modules under `src/` by `bash src/build.sh` and committed. Edit the modules, rebuild, run the four fast suites, and commit the regenerated bundle together with the change. The details live in `docs/`:

- [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md): prerequisites, first build, layout, conventions.
- [`docs/architecture.md`](docs/architecture.md): internal naming, module responsibilities, lifecycle, transport invariants, exit codes.
- [`docs/testing.md`](docs/testing.md): what each suite covers, what is not covered, the integration suite, shellcheck.
- [`docs/workflow.md`](docs/workflow.md): how a change gets from a branch to `main`.
- [`docs/release.md`](docs/release.md): how to cut a version.
- [`docs/decisions.md`](docs/decisions.md) and [`docs/history.md`](docs/history.md): why things are the way they are, and what happened when.
- [`docs/review-2026-11-06.md`](docs/review-2026-11-06.md): the last full review and its open items, tracked in the [issues](https://github.com/SEPANDESTAN/remote-scrcpy/issues).

AI coding agents start at [`AGENTS.md`](AGENTS.md), which links the same material and the procedures under `.agents/skills/`.

## Remote server and phone preparation

Use `remote-scrcpy --prerequisites` for the current generic checklist. That command is designed for later site-specific instructions, once details are provided. Do not invent platform-specific commands; add exact steps for the remote operating system, Android models, USB permissions and SSH policy once verified.

> **TODO** — the site-specific portion of the prerequisites is intentionally still a placeholder. Expansion is tracked in [issue #1](https://github.com/SEPANDESTAN/remote-scrcpy/issues/1), which contains a questionnaire covering remote OS, USB permissions, phone models, SSH policy, auth, and recovery. Fill those in before turning the `[TODO]` markers in `src/prerequisites.sh` into prescriptive instructions.

## Tests and limits

```bash
bash -n remote-scrcpy.sh
bash tests/test-maintenance.sh
bash tests/test-completion.sh
bash tests/test-cli-ui-review.sh
bash tests/test-ssh-config.sh
```

These run without a network, a phone or root, and ignore any `REMOTE_SCRCPY_*` configuration in your shell. An integration fixture exercises real OpenSSH and ADB with simulated devices; it needs root, so CI runs it for you, and it is not required to install, build or run the launcher. See [`docs/testing.md`](docs/testing.md) for what each suite covers and what is not covered.

Supported expectations are intentionally explicit: this Bash implementation is verified primarily on Linux. It needs Bash 4.4+ and OpenSSH Unix-style control sockets. Do not assume every operating system/architecture is verified simply because the script contains no native embedded payload.
