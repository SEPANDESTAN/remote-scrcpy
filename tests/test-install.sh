#!/usr/bin/env bash
# Verify install.sh in a sandbox: a scratch HOME, a PATH of chosen tools and a
# fake curl. No network, and nothing outside the sandbox is written.
set -euo pipefail
# The suite must never see the developer's own launcher configuration: with a
# host exported, an inherited environment once made a check contact it.
unset "${!REMOTE_SCRCPY_@}" ADB REMOTE_ADB ADB_PORT SCRCPY NO_COLOR
# No child may inherit the caller's standard input. Bash started with -c in a
# cleared environment and with a socket there (an agent's tool, a remote
# command) takes itself for a remote shell and reads ~/.bashrc, which often
# sources the system-wide file too. Under the bare PATH used below, a
# command-not-found handler defined there called a missing command from
# inside itself and forked without end.
exec < /dev/null
project=$(cd -- "$(dirname -- "$0")/.." && pwd)
installer=$project/install.sh
bundle=$project/remote-scrcpy.sh
passed=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
check() { "$@" || fail "$*"; passed=$((passed+1)); }
contains() { [[ $1 == *"$2"* ]]; }
lacks() { [[ $1 != *"$2"* ]]; }
equals() { [[ $1 == "$2" ]]; }

sandbox=$(mktemp -d)
trap 'rm -rf -- "$sandbox"' EXIT
home=$sandbox/home
bin=$sandbox/bin            # what the installer itself needs, and the fake curl
tools=$sandbox/tools        # stand-ins for ssh, adb and scrcpy
mkdir "$home" "$bin" "$tools" "$sandbox/work"
real_bash=$(command -v bash)
for tool in bash mkdir mktemp chmod mv rm cp grep; do
    ln -s "$(command -v "$tool")" "$bin/$tool"
done
for tool in ssh adb scrcpy; do
    printf '#!%s\nexit 0\n' "$real_bash" > "$tools/$tool"
    chmod +x "$tools/$tool"
done
# The fake curl records its arguments and writes what the file `curl-serves`
# names to the -o target: the bundle, a script that stops parsing after its
# first command, a script that is not the launcher, or nothing with curl's
# status for an HTTP error.
garbage_ran=$(printf '%q' "$sandbox/garbage-ran")
cat > "$bin/curl" <<CURL
#!$real_bash
printf '%s\n' "\$*" >> '$sandbox/curl.log'
while (( \$# )); do [[ \$1 == -o ]] && output=\$2; shift; done
case \$(< '$sandbox/curl-serves') in
    bundle) cp '$bundle' "\$output" ;;
    garbage) printf ': > %s\nif then\n' '$garbage_ran' > "\$output" ;;
    stranger) printf 'echo hello\n' > "\$output" ;;
    *) exit 22 ;;
esac
CURL
chmod +x "$bin/curl"
printf 'bundle\n' > "$sandbox/curl-serves"

# Run the installer with nothing inherited, in the directory `where`. The
# first argument is the PATH. Standard output lands in `output`, standard
# error in `messages`, the status in `result`.
where=$sandbox/work
extra_environment=()
run() {
    local path=$1; shift
    result=0
    output=$(cd "$where" && env -i HOME="$home" PATH="$path" "${extra_environment[@]}" "$real_bash" "$@" 2> "$sandbox/stderr" < /dev/null) || result=$?
    messages=$(< "$sandbox/stderr")
}
# The same for an installer that arrives on standard input, as from curl; the
# file to feed it is `piped_file`.
piped_file=$installer
run-piped() {
    local path=$1; shift
    result=0
    output=$(cd "$where" && env -i HOME="$home" PATH="$path" "$real_bash" -s -- "$@" 2> "$sandbox/stderr" < "$piped_file") || result=$?
    messages=$(< "$sandbox/stderr")
}
version=$("$real_bash" "$bundle" --version) || fail "the launcher's --version ended with status $?"
main_url=https://raw.githubusercontent.com/SEPANDESTAN/remote-scrcpy/main/remote-scrcpy.sh

# --help explains the script and does nothing else.
run "$bin" "$installer" --help
check equals "$result" 0
check contains "$output" 'Usage: install.sh [--dir DIR] [--ref REF] [--completion]'
check equals "$messages" ''
# What it cannot use is refused with status 2 before anything is written.
for arguments in '--bogus' 'extra' '--dir' '--dir=' '--ref' '--ref=a b' '--ref=../main' '--ref=-x' '--ref=a..b'; do
    read -r -a words <<< "$arguments"
    [[ $arguments != '--ref=a b' ]] || words=('--ref=a b')
    run "$bin" "$installer" "${words[@]}"
    equals "$result" 2 || fail "status $result instead of 2 for: $arguments"
done
passed=$((passed+1))
check equals "$(ls -A "$home" "$sandbox/work")" "$home:

$sandbox/work:"
[[ ! -e $sandbox/curl.log ]] || fail 'a usage error reached curl'

# From a checkout: the bundle next to the installer, no network, no ~/.bashrc.
run "$bin" "$installer"
check equals "$result" 0
check cmp -s "$bundle" "$home/.local/bin/remote-scrcpy"
check test -x "$home/.local/bin/remote-scrcpy"
check equals "$(ls -A "$home/.local/bin")" 'remote-scrcpy'
check test ! -e "$sandbox/curl.log"
check test ! -e "$home/.bashrc"
check contains "$messages" "Installed $version as $home/.local/bin/remote-scrcpy"
# It says what is still missing: the directory on PATH, the three programs,
# and how to get completion. All of it is a message: nothing on stdout.
check contains "$messages" "Note: $home/.local/bin is not on PATH."
check contains "$messages" 'Note: not found on PATH: ssh adb scrcpy.'
check contains "$messages" '  source <(remote-scrcpy --completion bash)'
check equals "$output" ''
# With everything in place it says none of that.
run "$bin:$tools:$home/.local/bin" "$installer"
check equals "$result" 0
check lacks "$messages" 'Note:'
# Run by its bare name inside a checkout, as the README says, it finds the
# bundle next to itself too.
mkdir "$sandbox/checkout"
cp "$installer" "$bundle" "$sandbox/checkout/"
where=$sandbox/checkout
run "$bin" install.sh --dir "$sandbox/by-name"
where=$sandbox/work
check equals "$result" 0
check cmp -s "$bundle" "$sandbox/by-name/remote-scrcpy"
check test ! -e "$sandbox/curl.log"

# --dir, also relative and with a space; an existing file is replaced, and
# only the launcher is left in the directory.
mkdir -p "$sandbox/work/my bin"
printf 'old\n' > "$sandbox/work/my bin/remote-scrcpy"
run "$bin" "$installer" --dir 'my bin'
check equals "$result" 0
check contains "$messages" "Installed $version as $sandbox/work/my bin/remote-scrcpy"
check cmp -s "$bundle" "$sandbox/work/my bin/remote-scrcpy"
check equals "$(ls -A "$sandbox/work/my bin")" 'remote-scrcpy'
run "$bin" "$installer" "--dir=$sandbox/other"
check cmp -s "$bundle" "$sandbox/other/remote-scrcpy"
# A ~ after = is not expanded by the shell; the installer does it.
run "$bin" "$installer" '--dir=~/tilde bin'
check equals "$result" 0
check cmp -s "$bundle" "$home/tilde bin/remote-scrcpy"
check test ! -e "$sandbox/work/~"
# A relative name is that name here, whatever CDPATH offers, and "-" is a
# directory, not the previous one.
mkdir -p "$sandbox/elsewhere/sub"
extra_environment=(CDPATH="$sandbox/elsewhere" OLDPWD="$sandbox/elsewhere")
run "$bin" "$installer" --dir sub
check cmp -s "$bundle" "$sandbox/work/sub/remote-scrcpy"
run "$bin" "$installer" --dir -
check cmp -s "$bundle" "$sandbox/work/-/remote-scrcpy"
check equals "$(ls -A "$sandbox/elsewhere" "$sandbox/elsewhere/sub")" "$sandbox/elsewhere:
sub

$sandbox/elsewhere/sub:"
extra_environment=()
# A directory of that name is not overwritten.
mkdir -p "$sandbox/blocked/remote-scrcpy"
run "$bin" "$installer" --dir "$sandbox/blocked"
check equals "$result" 1
check equals "$(ls -A "$sandbox/blocked")" 'remote-scrcpy'

# --completion adds one marked line to ~/.bashrc, keeps what is there, and
# does not add it twice.
printf 'export EXISTING=1' > "$home/.bashrc"
run "$bin" "$installer" --completion
check equals "$result" 0
check contains "$messages" 'Added Tab completion to ~/.bashrc'
check equals "$(grep -c 'added by install.sh' "$home/.bashrc")" 1
check equals "$(sed -n 1p "$home/.bashrc")" 'export EXISTING=1'
run "$bin" "$installer" --completion
check contains "$messages" 'Tab completion is already set up'
check equals "$(grep -c 'remote-scrcpy --completion bash' "$home/.bashrc")" 1
# The line registers the completion although the launcher's directory is not
# on PATH, as in a login shell that reads ~/.bashrc first, and it is silent
# once the launcher is gone. --norc and the sandbox HOME keep the shell that
# tries it away from the real startup files whatever its standard input is.
# shellcheck disable=SC2016  # scripts for the shell under test; they must expand there
printf 'source "$HOME/.bashrc" && complete -p remote-scrcpy\n' > "$sandbox/try-registered.sh"
# shellcheck disable=SC2016
printf 'source "$HOME/.bashrc"; echo "status $?"\n' > "$sandbox/try-silent.sh"
try() { env -i HOME="$home" PATH="$bin" "$real_bash" --norc "$sandbox/try-$1.sh" 2>&1 < /dev/null; }
check equals "$(try registered)" 'complete -F _complete-remote-scrcpy remote-scrcpy'
mv "$home/.local/bin/remote-scrcpy" "$sandbox/set-aside"
check equals "$(try silent)" 'status 0'
mv "$sandbox/set-aside" "$home/.local/bin/remote-scrcpy"
# Installed somewhere else afterwards, the existing line is not touched and
# not called set up either: the message shows the line for the new place.
run "$bin" "$installer" --dir "$sandbox/second place" --completion
check equals "$result" 0
check contains "$messages" 'was not written for'
check contains "$messages" "  if [[ -x $(printf '%q' "$sandbox/second place/remote-scrcpy") ]]; then source <("
check equals "$(grep -c 'added by install.sh' "$home/.bashrc")" 1
# A home without a ~/.bashrc gets one that holds just that line.
home=$sandbox/fresh-home
mkdir "$home"
run "$bin" "$installer" --completion
check equals "$(grep -c '' "$home/.bashrc")" 1
check contains "$(< "$home/.bashrc")" '--completion bash); fi  # remote-scrcpy completion (added by install.sh)'
# A ~/.bashrc that already loads the completion, as the README shows, is
# left as it is.
home=$sandbox/hand-home
mkdir "$home"
printf 'source <(remote-scrcpy --completion bash)\n' > "$home/.bashrc"
run "$bin" "$installer" --completion
check contains "$messages" 'was not written for'
check equals "$(< "$home/.bashrc")" 'source <(remote-scrcpy --completion bash)'
# A path that needs quoting gives a line that still works.
home=$sandbox/quoted-home
mkdir "$home"
run "$bin" "$installer" --dir "$sandbox/it's here" --completion
check equals "$result" 0
check equals "$(try registered)" 'complete -F _complete-remote-scrcpy remote-scrcpy'
run "$bin" "$installer" --dir "$sandbox/it's here" --completion
check contains "$messages" 'Tab completion is already set up'
check equals "$(grep -c '' "$home/.bashrc")" 1
# So does a path that the shell can only write as $'...', and there only the
# marker says that the line is a completion line when another place asks.
home=$sandbox/tab-home
mkdir "$home"
run "$bin" "$installer" --dir "$sandbox/with"$'\t'"tab" --completion
check equals "$(try registered)" 'complete -F _complete-remote-scrcpy remote-scrcpy'
run "$bin" "$installer" --dir "$sandbox/with"$'\t'"tab" --completion
check contains "$messages" 'Tab completion is already set up'
run "$bin" "$installer" --dir "$sandbox/other" --completion
check contains "$messages" 'was not written for'
check equals "$(grep -c '' "$home/.bashrc")" 1
home=$sandbox/home

# Read from a pipe there is no checkout: it downloads the main branch.
run-piped "$bin" --dir "$sandbox/piped"
check equals "$result" 0
check cmp -s "$bundle" "$sandbox/piped/remote-scrcpy"
check contains "$(< "$sandbox/curl.log")" "$main_url"
# A file named remote-scrcpy.sh where the pipe is run is not taken for one.
cp "$bundle" "$sandbox/work/remote-scrcpy.sh"
: > "$sandbox/curl.log"
run-piped "$bin" --dir "$sandbox/piped"
check contains "$(< "$sandbox/curl.log")" "$main_url"
# So does a copy of the installer that has no bundle next to it.
mkdir "$sandbox/lone"
cp "$installer" "$sandbox/lone/install.sh"
: > "$sandbox/curl.log"
run "$bin" "$sandbox/lone/install.sh" --dir "$sandbox/lone/bin"
check contains "$(< "$sandbox/curl.log")" "$main_url"
check cmp -s "$bundle" "$sandbox/lone/bin/remote-scrcpy"
# --ref names the version and downloads even from a checkout.
: > "$sandbox/curl.log"
run "$bin" "$installer" --ref v3.0.2 --dir "$sandbox/piped"
check equals "$result" 0
check contains "$(< "$sandbox/curl.log")" 'https://raw.githubusercontent.com/SEPANDESTAN/remote-scrcpy/v3.0.2/remote-scrcpy.sh'

# A download that fails, is not Bash, or is not the launcher installs
# nothing: the existing launcher stays and no temporary file is left.
printf 'old\n' > "$sandbox/piped/remote-scrcpy"
for served in missing garbage stranger; do
    printf '%s\n' "$served" > "$sandbox/curl-serves"
    run-piped "$bin" --dir "$sandbox/piped"
    equals "$result" 1 || fail "status $result instead of 1 for a download that is $served"
    equals "$(< "$sandbox/piped/remote-scrcpy")" 'old' || fail "a download that is $served replaced the launcher"
    equals "$(ls -A "$sandbox/piped")" 'remote-scrcpy' || fail "a download that is $served left a file behind"
    passed=$((passed+1))
done
# A file that does not parse is not run at all, not even its first lines.
check test ! -e "$sandbox/garbage-ran"
# An installer that arrives cut short installs nothing. Its last line is the
# one that starts the work, so every cut inside that line is tried.
# A cut that drops the arguments would install into the default directory,
# so an empty home is what has to stay empty.
printf 'bundle\n' > "$sandbox/curl-serves"
size=$(wc -c < "$installer")
last_line=$(tail -n 1 "$installer")
piped_file=$sandbox/cut-installer
home=$sandbox/cut-home
mkdir "$home"
for (( cut = size - ${#last_line} - 1; cut < size - 1; cut++ )); do
    head -c "$cut" "$installer" > "$piped_file"
    run-piped "$bin" --dir "$sandbox/cut"
    [[ ! -e $sandbox/cut && -z $(ls -A "$home") ]] || fail "an installer cut at byte $cut of $size installed something"
done
passed=$((passed+1))
piped_file=$installer
home=$sandbox/home
# Without curl it says so with the status for a missing program.
rm "$bin/curl"
run-piped "$bin" --dir "$sandbox/piped"
check equals "$result" 127
check contains "$messages" 'curl is needed'
check equals "$(ls -A "$sandbox/piped")" 'remote-scrcpy'

printf 'Install checks: %d passed.\n' "$passed"
