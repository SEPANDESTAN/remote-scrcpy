# Extended, self-contained setup guide. Intentionally contains only established
# prerequisites; site-specific policies are left as explicit placeholders until
# the maintainer supplies exact remote-server and phone preparation steps.
# No commands are executed in this mode.
# Show detailed local/remote/phone preparation checklist.
# Static stdout; includes TODOs awaiting user’s site-specific instructions.
_print-prerequisites() {
    local line
    while IFS= read -r line; do printf '%s\n' "$line"; done <<'GUIDE'
REMOTE SCRCPY — PREREQUISITES & PREPARATION
==========================================

1. VIEWING COMPUTER (the machine running remote-scrcpy)
   - Linux or another TESTED Unix-like environment with Bash >= 4.4.
   - OpenSSH client (`ssh`) with multiplexing and local TCP forwarding.
   - `scrcpy` installed and a usable `adb` client available. Some scrcpy
     packages depend on or bundle adb; this launcher still invokes adb itself
     to enumerate devices and configure forwarding. Check `command -v adb`.
   - A graphical desktop with video support for the scrcpy window.
   - Standard tools: awk, mktemp, rm, sleep. No extra terminal UI dependency.

   Check:
     bash --version
     ssh -V
     adb version
     scrcpy --version

2. REMOTE COMPUTER (phone is attached here)
   - Reachable SSH server and credentials/key for the SSH user.
   - `adb` accessible from that user's noninteractive SSH shell, or provide
     `--remote-adb /absolute/path/to/adb`.
   - Permit local TCP forwarding through SSH (sshd policy AllowTcpForwarding).
   - Same or compatible ADB client/server protocol as the viewing computer.
   - Authorized USB access for the remote user. Verify:
       ssh HOST 'adb start-server && adb devices -l'

   IMPORTANT: The launcher reuses remote ADB and does not deliberately stop
   an existing remote ADB server. ADB authorization is specific to the host
   user/configuration; do not run it under a different user unexpectedly.

3. ANDROID PHONE(S)
   - Enable Developer options and USB debugging through Android settings.
   - Plug the phone into the REMOTE computer using a data-capable cable.
   - Unlock the phone and approve the remote computer's RSA debugging prompt.
   - Confirm `adb devices -l` on the remote reports the state `device`.
   - `unauthorized`: confirm the on-phone authorization prompt.
   - `offline`: reconnect/restart ADB and inspect USB connectivity.
   - `no permissions`: correct the remote Linux user/udev USB permissions.

4. SSH ALIASES AND FIREWALL
   Optionally add a readable SSH alias in ~/.ssh/config, for example:

     Host alienware
         HostName 192.0.2.10
         User myuser

   Replace the example address and username. The launcher shows literal Host
   aliases; you can also enter any valid SSH destination manually.
   Only SSH needs to be accessible over the network; forwarding ports bind
   on loopback and are routed through the authenticated SSH session.

5. SITE-SPECIFIC SETUP (TO BE PROVIDED BY THE MAINTAINER)
   [TODO: Add remote server provisioning steps, packages, service setup,
    SSH hardening decisions, USB permissions, ADB startup procedures, and
    any site-specific reconnect or recovery steps.]

   [TODO: Add phone-specific instructions for each Android version/model,
    charging/USB restrictions, authorization lifecycle, and any security
    guidance relevant to the phones being used.]

   Please supply exact OS, device model, installation and authorization
   procedures before turning these TODOs into prescriptive instructions.

6. TROUBLESHOOTING
   - `remote-scrcpy --list-hosts` lists aliases locally, without SSH.
   - `remote-scrcpy --list-devices HOST` checks remote discovery without GUI.
   - `remote-scrcpy --verbose HOST SERIAL` prints SSH/ADB diagnostics.
   - `ADB server mismatch`: align Android Platform Tools versions; the
     launcher does not forcibly restart an incompatible shared server.
   - scrcpy SDL/display errors: run on the viewer's graphical desktop,
     not from an ordinary SSH shell on the remote computer.
   - Review scrcpy's own documentation for platform-specific requirements.

Security: USB debugging and SSH access give powerful control of the phone.
Only authorize computers and accounts you trust. Keep forwarding local.
GUIDE
}
