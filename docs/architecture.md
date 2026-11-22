# Architecture

How `remote-scrcpy.sh` is put together and the invariants that keep it
correct. The rules for changing it are in [`CONTRIBUTING.md`](CONTRIBUTING.md);
the reasons behind the design are in [`decisions.md`](decisions.md).

## Modules

`remote-scrcpy.sh` at the repository root is the only file needed at
runtime. `bash src/build.sh` generates it by writing a header and then the
nine modules under `src/`, in this order:

| Module | Responsibility |
|---|---|
| `core.sh` | configuration defaults from the environment, validation, logging, resolving the local executables; holds the glossary of shared state |
| `cli.sh` | argument parsing, help text, precedence; no network access |
| `ssh-config.sh` | static discovery of host aliases; an SSH configuration is read as data and never interpreted |
| `presentation.sh` | colors and symbols for stderr; stdout stays plain |
| `ui.sh` | numbered host and device menus, device listing |
| `transport.sh` | SSH master, port forwards, ADB protocol probe, scrcpy launch and cleanup; owns every `SESSION_*` variable |
| `prerequisites.sh` | the static setup guide, with marked placeholders for site-specific steps |
| `completion.sh` | prints the Bash completion script; that script never opens the tunnel or a window, and its device lookup is one read-only SSH query, bounded where `timeout` is installed |
| `main.sh` | `remote-scrcpy`, the single public function: lifecycle and traps |

The header that `src/build.sh` writes carries the usage summary a reader of
the bundle sees first, and the Bash version guard.

## Internal naming

Shell variables are grouped by prefix. They are internal; the supported
interface is the command line and the `REMOTE_SCRCPY_*` environment
variables.

| Group | Purpose | Example |
|---|---|---|
| `SETTINGS_*` | parsed options and environment defaults | `SETTINGS_SSH_HOST`, `SETTINGS_DEVICE_SERIAL` |
| `SESSION_*` | resources owned by the active connection; transport only | `SESSION_SSH_CONTROL_SOCKET`, `SESSION_LOCAL_ADB_TUNNEL_PORT` |
| `DISCOVERED_DEVICE_*` | parallel arrays of remote device metadata | `DISCOVERED_DEVICE_SERIALS` |
| `DISPLAY_*` | terminal escape codes and symbols | `DISPLAY_COLOR_WARNING` |
| `CLI_*` | which arguments were given explicitly | `CLI_HOST_EXPLICIT` |
| `INPUT_RESPONSE` | the last answer read at a prompt | |
| `APPLICATION_VERSION` | the program version | |

The one public function is `remote-scrcpy`; helpers start with `_` and have
kebab-case names that say what they do.

## Lifecycle walk-through

`remote-scrcpy()` in `src/main.sh` is the whole program:

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
  failed to remove. Simultaneous sessions therefore never share a port, and
  the device and tunnel flags are the launcher's: passing them after `--` is
  refused.
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

## Upstream references

What the invariants above rely on, and where each is stated.

| Fact | Source |
|---|---|
| scrcpy's `--force-adb-forward`, `--tunnel-host`, `--tunnel-port` and `--port`, and running it through an SSH tunnel | [scrcpy: tunnels](https://github.com/Genymobile/scrcpy/blob/master/doc/tunnels.md) |
| scrcpy is built on SDL, which installs handlers for SIGINT and SIGTERM and turns them into a quit event; it lists none for SIGHUP, which is why a received HUP is forwarded as TERM | [scrcpy: build](https://github.com/Genymobile/scrcpy/blob/master/doc/build.md) for the dependency, [SDL: `SDL_HINT_NO_SIGNAL_HANDLERS`](https://wiki.libsdl.org/SDL2/SDL_HINT_NO_SIGNAL_HANDLERS) for the handlers |
| `ADB_SERVER_SOCKET` tells the adb client, and scrcpy through it, which server to talk to | [scrcpy: tunnels](https://github.com/Genymobile/scrcpy/blob/master/doc/tunnels.md) |
| `adb forward` accepts `tcp:0` to pick any open port | [adb manual page](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/user/adb.1.md) |
| it then prints the port it picked | observed, not documented there: the launcher reads that line, and the integration suite exercises it with a real adb |
| `host:version` is the request that returns the server's protocol version | [adb: services](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/services.md) |
| a host-less `tcp:PORT` counts as a local server, which the client may start; a server whose version differs from the client's is killed and restarted by the client ("doesn't match this client; killing...") | adb source: [`socket_spec.cpp`](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/socket_spec.cpp) (`is_local_socket_spec`) and [`client/adb_client.cpp`](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/client/adb_client.cpp) |
| `ControlMaster`, `ControlPath`, `-O check`, `-O forward` and `-O exit` | [ssh(1)](https://man.openbsd.org/ssh) and [ssh_config(5)](https://man.openbsd.org/ssh_config) |
| `NO_COLOR` is a default for programs that color on their own; a setting made for the program overrides it | [no-color.org](https://no-color.org/) |
