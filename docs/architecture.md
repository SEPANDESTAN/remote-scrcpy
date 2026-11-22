# Architecture

How `remote-scrcpy.sh` is put together and the rules that keep it correct.
The first two sections were moved here from the README on 2026-11-19 without
change; the rest was added from the 2026-11-06 review.

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

## Lifecycle walk-through

`remote-scrcpy()` in `src/main.sh` is the whole program in forty lines:

1. `_initialize-configuration` (environment defaults), `_parse-command-line`,
   `_validate-configuration`, `_validate-scrcpy-arguments`,
   `_initialize-terminal-styles`. Any usage error exits 2 here, before traps
   or network.
2. Help-like modes return early: `--prerequisites`, `--completion bash`, and
   `--list-hosts` (alias discovery only, needs `awk`, never SSH).
3. Traps are installed: `_handle-process-exit` on EXIT,
   `_handle-termination-signal` for INT/TERM/HUP with exit codes 130/143/129.
   Only now may anything allocate a resource.
4. `_check-runtime-dependencies` resolves `adb` (and `scrcpy` for connect) to
   absolute paths; missing tools exit 127.
5. Host prompt if needed; a missing serial without a terminal exits 2 before
   connecting.
6. `_open-remote-connection` (`src/transport.sh`): private work directory,
   SSH master, `-O check`, local forward to the remote ADB port, local `adb
   version`, protocol probe, optional remote `start-server`, protocol match.
7. `_load-remote-device-list`, then `--list-devices` returns, or the device
   prompt and `_validate-selected-device`.
8. `_reserve-device-forwarding-port`, then `_launch-scrcpy`; scrcpy's exit
   status becomes the launcher's.
9. The EXIT trap runs `_cleanup-remote-connection` on every path after step 3,
   including partial setup.

## Transport invariants and why

- **`set -m` around the scrcpy launch** puts scrcpy in its own process group
  without a `setsid` dependency. Ctrl-C therefore hits the launcher only;
  `_stop-scrcpy-process` forwards one signal, waits up to 5 s, then sends
  TERM and KILL to the group. A received HUP is forwarded as TERM, because
  scrcpy shuts down cleanly on INT and TERM only; the launcher still exits
  with 129. Every group kill is gated by `kill -0`, and the
  PID comes only from `$!`, so PID 0, 1 or an empty value can never be
  targeted.
- **The mux client uses `-F /dev/null -o ProxyCommand=false -o
  ControlMaster=no`.** It must only ever talk to the socket the master
  created; if the socket is gone it must fail, never open a fresh
  connection using the user's config. The master itself does read the user's
  config (or `--ssh-config`) and overrides forwardings, `RemoteCommand`,
  agent and X11 forwarding on the command line.
- **`/tmp` is hardcoded for the work directory** (`mktemp -d
  /tmp/remote-scrcpy.XXXXXXXX`, mode 0700). Unix socket paths are limited to
  about 108 bytes, and `TMPDIR` can be arbitrarily long.
- **Local forwards bind `127.0.0.1` explicitly** (`-L
  127.0.0.1:LOCAL:127.0.0.1:REMOTE` through `-O forward`), so `GatewayPorts`
  in a config cannot widen them. Ports are random in 20000–59999 with the SSH
  bind as the reservation; a collision is retried.
- **`tcp:PORT` versus `tcp:127.0.0.1:PORT`.** adb treats a host-less
  `tcp:PORT` as local and may start a server for it; that form is used only
  in the remote `exec env ADB_SERVER_SOCKET=tcp:PORT adb start-server`
  command. Every local adb call and the scrcpy environment use
  `tcp:127.0.0.1:TUNNEL_PORT`, which adb treats as remote and never
  auto-starts.
- **The protocol probe reads `host:version` itself** over `/dev/tcp`, with
  `read -N -t 5` bounding every read and strict checks on status, length and
  payload. Only a clean close or refusal (status 2) triggers a remote
  `start-server`; anything malformed (status 1) aborts. A protocol mismatch
  aborts before any adb client command, because an adb client would kill
  and restart the mismatched shared server.
- **Remote media port by `adb forward tcp:0` with a unique token**
  (`localabstract:remote_scrcpy_<workdir>_<random>`). scrcpy is launched with
  `--force-adb-forward --port=REMOTE --tunnel-host=127.0.0.1
  --tunnel-port=LOCAL` and rebinds that port to its own socket. Cleanup
  removes a forward only when serial, port form and the exact token match;
  a port that another session obtained later is never touched, at the price
  of leaving behind a forward that this session's scrcpy rebound and then
  failed to remove.
- **Remote output is data.** `adb devices -l` and `forward --list` rows are
  read with `read -r` into variables, compared with quoted `==`, and never
  globbed, evaluated or used in a path. Device names are passed through
  `_sanitize-display-text` before display.
- **Remote command strings** exist in exactly two places: the `start-server`
  command in `_open-remote-connection` and the `adb devices -l` query in the
  completion function. Both are built from locally validated values through
  POSIX single-quote escaping, which works for `sh`, `dash`, `bash`, `zsh`
  and `ksh` login shells.

## Bash floor

The bundle requires Bash 4.4. The binding feature is `"${array[@]}"` on an
empty array under `set -u`, used for the scrcpy pass-through arguments and
several internal lists. Other features and their minimums: `read -N` and
`{fd}<>` redirections (4.1), `mapfile` and `${var,,}` (4.0), `printf -v` and
`+=` on arrays (3.1), `[[ =~ ]]` (3.0). Nothing from Bash 5 is used. The
version guard is the first executable statement of the bundle, before `set
-Eeuo pipefail` and before any function definition, so Bash 3.2 (macOS
`/bin/bash`) prints one line and exits 2 instead of failing to parse. The
`/dev/tcp` probe additionally needs a Bash built with network redirections,
which every mainstream distribution enables.

## Exit codes

A status has one of two sources. Until scrcpy is started it is the
launcher's own; once scrcpy runs, scrcpy's status is passed on unchanged,
and scrcpy uses 1 and 2 for failures of its own, so those two values alone
do not say which program failed.

| Code | Meaning |
|---|---|
| 0 | a listing or help mode completed, or scrcpy exited 0 |
| 1 | launcher: runtime failure before scrcpy started (SSH, ADB, forwarding, protocol mismatch) |
| 2 | launcher: usage or configuration error; nothing was connected |
| 127 | launcher: a required executable is missing |
| 130 | cancelled (`q`, EOF at a prompt) or SIGINT, at any time |
| 143 / 129 | SIGTERM / SIGHUP received, at any time |
| any | scrcpy's own exit status once it runs, including its own 1 and 2 |
