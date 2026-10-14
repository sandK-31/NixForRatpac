#!/usr/bin/env bash
# NixForRatpac test suite, native Linux. From the repo, in a terminal on the
# desktop (not over plain SSH, or the GUI tests skip):
#   tests/linux/run-tests.sh            (--help for options)
# On an X11-only desktop add --qpa xcb; see the session check below.

NFR_OS=linux
. "$(cd "$(dirname "$0")" && pwd)/../common/harness.sh"

t_linux_distro() {
  local name
  name=$( (. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") || uname -o)
  echo "$name / $(uname -srm) / nix system $NFR_SYSTEM"
  if grep -qi microsoft /proc/version 2>/dev/null; then
    note "this is WSL: use tests/windows/run-tests.sh, which also checks WSLg"
    return "$WARN"
  fi
  note "$name, $(uname -m)"
}

# The dev shell exports QT_QPA_PLATFORM=wayland and DISPLAY=:0 whatever the
# desktop is, so say up front where that will not work.
t_linux_session() {
  echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-} DISPLAY=${DISPLAY:-}"
  if [ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
    note "no display (SSH or console?): GUI tests will be skipped"
    return "$WARN"
  fi
  if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "$NFR_QPA_OVERRIDE" ]; then
    note "X11-only desktop: the shell forces QT_QPA_PLATFORM=wayland, so Qt windows will fail; rerun with --qpa xcb to test X11"
    return "$WARN"
  fi
  if [ -n "${DISPLAY:-}" ] && [ "$DISPLAY" != :0 ]; then
    note "DISPLAY is $DISPLAY but the shell resets it to :0, so X11 windows (ROOT) may fail"
    return "$WARN"
  fi
  note "${XDG_SESSION_TYPE:-?} session, WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-none} DISPLAY=${DISPLAY:-none}${NFR_QPA_OVERRIDE:+, GUI tests use $NFR_QPA_OVERRIDE}"
}

os_preflight() {
  run_test distro  "Distribution"    t_linux_distro
  run_test session "Desktop session" t_linux_session
}

gui_available() {
  [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]
}

main "$@"
