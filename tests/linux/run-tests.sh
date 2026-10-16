#!/usr/bin/env bash
# NixForRatpac test suite, native Linux. From the repo, in a terminal on the
# desktop (not over plain SSH, or the GUI tests skip):
#   tests/linux/run-tests.sh            (--help for options)

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

# What the GUI tests will use. The shell defaults Qt to wayland when there is
# a compositor and xcb otherwise, and off NixOS brings its own Mesa for
# OpenGL, which can't drive NVIDIA's proprietary driver.
t_linux_session() {
  echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-} DISPLAY=${DISPLAY:-}"
  if [ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
    note "no display (SSH or console?): GUI tests will be skipped"
    return "$WARN"
  fi
  local qpa=${NFR_QPA_OVERRIDE:-xcb}
  [ -z "$NFR_QPA_OVERRIDE" ] && [ -n "${WAYLAND_DISPLAY:-}" ] && qpa=wayland
  local gl="Mesa from the shell"
  [ -d /run/opengl-driver/lib ] && gl="NixOS's OpenGL driver"
  if [ -e /proc/driver/nvidia/version ] && [ ! -d /run/opengl-driver/lib ]; then
    head -n 1 /proc/driver/nvidia/version
    note "NVIDIA proprietary driver: the shell's Mesa can't use it, so OpenGL viewers may fall back to software or fail; Qt uses $qpa"
    return "$WARN"
  fi
  note "${XDG_SESSION_TYPE:-?} session; Qt uses $qpa, OpenGL via $gl"
}

os_preflight() {
  run_test distro  "Distribution"    t_linux_distro
  run_test session "Desktop session" t_linux_session
}

gui_available() {
  [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]
}

main "$@"
