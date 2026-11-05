#!/usr/bin/env bash
# Bundle maintained modules into one portable-to-copy Bash executable.
set -euo pipefail
script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "$script_dir/.." && pwd)
output=${1:-$project_dir/remote-scrcpy.sh}
build_tmp=$(mktemp "${output}.build.XXXXXX")
trap 'rm -f -- "$build_tmp"' EXIT

cat > "$build_tmp" <<'HEADER'
#!/usr/bin/env bash
# =============================================================================
# remote-scrcpy — View/control an Android phone over SSH from this computer.
# =============================================================================
# PURPOSE
#   Runs scrcpy locally while an Android phone remains connected by USB to an
#   SSH-accessible remote computer. The remote computer's authorized ADB server
#   is accessed through temporary SSH tunnels; no display server is needed on
#   the remote computer. Each invocation owns and cleans up its SSH resources.
#
# INSTALL ON THE VIEWING COMPUTER
#   1. Install Bash 4.4+, an OpenSSH client, adb, and scrcpy (with a GUI session).
#   2. Copy this script and make it executable:
#        mkdir -p "$HOME/.local/bin"
#        install -m 755 remote-scrcpy.sh "$HOME/.local/bin/remote-scrcpy"
#   3. Ensure ~/.local/bin is on PATH, or call the file as ./remote-scrcpy.sh.
#   On the REMOTE computer, enable SSH forwarding and authorize the Android
#   phone for USB debugging. See the detailed, updatable preparation guide:
#        remote-scrcpy --prerequisites
#
# BASIC USAGE
#        remote-scrcpy --help
#        remote-scrcpy --prerequisites
#        remote-scrcpy                      # choose SSH host, then phone
#        remote-scrcpy remote-host            # choose phone on SSH host
#        remote-scrcpy remote-host SERIAL     # connect without prompts
#        remote-scrcpy --list-hosts
#        remote-scrcpy --list-devices remote-host
#   Enable Bash completion in your interactive shell (optional):
#        source <(remote-scrcpy --completion bash)
#
# CONFIGURATION AND MAINTENANCE
#   CLI flags override REMOTE_SCRCPY_* environment variables; see --help.
#   Internal SETTINGS_* globals hold resolved choices, SESSION_* globals hold
#   owned resources, and DISPLAY_*/DISCOVERED_DEVICE_* hold presentation/data.
#   Internal helpers are _prefixed-kebab-case; `remote-scrcpy` is the sole
#   public function. The single-file executable is assembled from documented
#   source modules by `bash src/build.sh`; edit those modules when available.
#   No external terminal UI framework or embedded binary payload is required.
# =============================================================================
if (( BASH_VERSINFO[0] < 4 || ( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4 ) )); then
    printf 'remote-scrcpy requires Bash 4.4 or newer.\n' >&2
    exit 2
fi
set -Eeuo pipefail
HEADER
for module in core cli ssh-config presentation ui transport prerequisites completion main; do
    printf '\n# ===== %s.sh =====\n' "$module" >> "$build_tmp"
    cat "$script_dir/$module.sh" >> "$build_tmp"
done
bash -n "$build_tmp"
chmod 755 "$build_tmp"
mv -- "$build_tmp" "$output"
printf 'Built %s\n' "$output"
