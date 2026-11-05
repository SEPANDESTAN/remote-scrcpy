#!/usr/bin/env bash
# Verify both local SSH-alias and live remote device completion without network.
set -euo pipefail
project=$(cd -- "$(dirname -- "$0")/.." && pwd)
script=$project/remote-scrcpy.sh
sandbox=$(mktemp -d)
trap 'rm -rf -- "$sandbox"' EXIT
mkdir "$sandbox/bin"
cat > "$sandbox/config" <<'CONFIG'
Host remote-host
Host remote-backup beta
CONFIG
cat > "$sandbox/bin/ssh" <<'SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SSH_COMPLETION_CALLS"
cat <<'DEVICES'
List of devices attached
DEVICE1234567890 device product:test model:Test_Phone_A
OFFLINE offline
Z99999 device product:other model:Another
UNAUTH unauthorized
DEVICES
SSH
chmod +x "$sandbox/bin/ssh"
# Keep timeout out of PATH intentionally: SSH options should still bound connects.
# Where available, GNU timeout is allowed, and delegates to our fake ssh.
export PATH="$sandbox/bin:$PATH"
export SSH_COMPLETION_CALLS="$sandbox/calls"
export REMOTE_SCRCPY_SSH_CONFIG="$sandbox/config"
source <("$script" --completion bash)
passed=0
assert_eq() {
    local label=$1 expected=$2 actual=$3
    [[ $expected == "$actual" ]] || { printf 'FAIL %s expected %q actual %q\n' "$label" "$expected" "$actual" >&2; exit 1; }
    ((passed+=1))
}
complete_words() {
    COMP_WORDS=("$script" "$@")
    COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
    COMPREPLY=()
    _complete-remote-scrcpy
}
complete_words r
assert_eq 'SSH aliases' 'remote-host remote-backup' "${COMPREPLY[*]}"
complete_words remote-host D
assert_eq 'serial positional' 'DEVICE1234567890' "${COMPREPLY[*]}"
complete_words --host remote-host D
assert_eq 'serial after named host' 'DEVICE1234567890' "${COMPREPLY[*]}"
complete_words --host=remote-h
assert_eq 'host equals' '--host=remote-host' "${COMPREPLY[*]}"
complete_words remote-host --serial=D
assert_eq 'serial equals' '--serial=DEVICE1234567890' "${COMPREPLY[*]}"
complete_words --host remote-host --serial Z
assert_eq 'serial with flag' 'Z99999' "${COMPREPLY[*]}"
complete_words --color=a
assert_eq 'color equals' '--color=auto --color=always' "${COMPREPLY[*]}"
count=$(wc -l < "$SSH_COMPLETION_CALLS")
assert_eq 'queries after six lookups' '4' "$count"
REMOTE_SCRCPY_COMPLETE_DEVICES=0
complete_words remote-host D
assert_eq 'disabled network serial' '' "${COMPREPLY[*]}"
assert_eq 'disabled network query count' "$count" "$(wc -l < "$SSH_COMPLETION_CALLS")"
unset REMOTE_SCRCPY_COMPLETE_DEVICES
# The chosen host must appear exactly once; do not introduce unsafe word splitting.
[[ $(tail -1 "$SSH_COMPLETION_CALLS") == *remote-host* ]] || exit 1
printf 'Completion checks: %d passed.\n' "$passed"
