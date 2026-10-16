#!/usr/bin/env bash
# NixForRatpac test suite, Windows. Nix only runs inside WSL 2, so run this
# from the Ubuntu terminal, in the clone under ~ (not /mnt/c):
#   tests/windows/run-tests.sh          (--help for options)
#
# Answer the "what did you see" questions honestly: under WSLg's COPY MODE bug
# every automated GUI check passes while Windows shows a blank window.

NFR_OS=windows
. "$(cd "$(dirname "$0")" && pwd)/../common/harness.sh"

t_wsl() {
  cat /proc/version
  grep -qi microsoft /proc/version || { note "not WSL: on Windows, run this inside the Ubuntu (WSL 2) terminal"; return 1; }
  local name
  name=$( (. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") || echo Linux)
  note "$name in WSL (${WSL_DISTRO_NAME:-distro?}), kernel $(uname -r)"
}

t_wsl_version() {
  local out
  out=$(with_timeout 20 wsl.exe --version 2>/dev/null | tr -d '\000\r')
  echo "$out"
  [ -n "$out" ] || { note "wsl.exe not reachable from Linux (interop off?); check 'wsl --version' in PowerShell"; return "$WARN"; }
  note "$(echo "$out" | grep -m1 -i 'wsl' ) / $(echo "$out" | grep -m1 -i 'wslg')"
}

t_systemd() {
  local s
  s=$(systemctl is-system-running 2>/dev/null)
  echo "systemctl is-system-running: $s"
  case $s in
    running | degraded) note "systemd $s" ;;
    *) note "systemd '$s': README step 3 (fine if you used the single-user Nix install)"; return "$WARN" ;;
  esac
}

t_repo_location() {
  case $NFR_REPO in
    /mnt/[a-z]/*)
      note "repo is on the Windows drive ($NFR_REPO): slow, and Nix lacks the permissions it wants; clone under ~"
      return "$WARN"
      ;;
  esac
  note "repo on the Linux filesystem ($NFR_REPO)"
}

t_disk() {
  local free
  free=$(df -Pk /nix 2>/dev/null | awk 'NR == 2 { print int($4 / 1048576) }')
  df -h /nix 2>/dev/null
  [ -n "$free" ] || { note "cannot read free space under /nix"; return "$WARN"; }
  [ "$free" -ge 20 ] || { note "$free GB free under /nix; a first build needs ~20 GB"; return "$WARN"; }
  note "$free GB free under /nix"
}

t_wslg() {
  ls -la /mnt/wslg 2>/dev/null | head -n 5
  echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-} DISPLAY=${DISPLAY:-}"
  [ -d /mnt/wslg ] && [ -n "${WAYLAND_DISPLAY:-}" ] \
    || { note "WSLg not running (no /mnt/wslg or WAYLAND_DISPLAY): 'wsl --update' in PowerShell, then 'wsl --shutdown'"; return 1; }
  note "WSLg up: WAYLAND_DISPLAY=$WAYLAND_DISPLAY DISPLAY=${DISPLAY:-none}"
}

# README > Troubleshooting > "[WARN: COPY MODE]".
t_wslg_copy_mode() {
  local line
  line=$(grep use_gfxredir /mnt/wslg/weston.log 2>/dev/null | tail -n 1)
  echo "${line:-no use_gfxredir line in /mnt/wslg/weston.log}"
  [ -n "$line" ] || { note "weston.log has no use_gfxredir line; can't tell"; return "$SKIP"; }
  case $line in
    *"use_gfxredir = 1"*) note "use_gfxredir = 1, healthy" ;;
    *)
      note "use_gfxredir = 0: COPY MODE, windows will be blank. Fix: wsl.exe -d \"$WSL_DISTRO_NAME\" --system -- sh -c 'kill \$(pgrep -x weston)', then rerun"
      return 1
      ;;
  esac
}

os_preflight() {
  run_test wsl           "Running inside WSL"     t_wsl
  run_test wsl-version   "WSL version"            t_wsl_version
  run_test systemd       "systemd"                t_systemd
  run_test repo-location "Repo location"          t_repo_location
  run_test disk          "Free space for /nix"    t_disk
  run_test wslg          "WSLg"                   t_wslg
  run_test wslg-copymode "WSLg COPY MODE bug"     t_wslg_copy_mode
}

gui_available() {
  [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]
}

main "$@"
