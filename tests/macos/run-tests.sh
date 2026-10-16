#!/usr/bin/env bash
# NixForRatpac test suite, macOS. From the repo, in Terminal:
#   tests/macos/run-tests.sh            (--help for options)

NFR_OS=macos
. "$(cd "$(dirname "$0")" && pwd)/../common/harness.sh"

t_macos_version() {
  sw_vers
  note "macOS $(sw_vers -productVersion), $(uname -m)"
}

t_macos_system() {
  echo "nix system: $NFR_SYSTEM"
  case $NFR_SYSTEM in
    aarch64-darwin) note "aarch64-darwin (Apple Silicon)" ;;
    x86_64-darwin)
      note "x86_64-darwin: nixpkgs 26.05 marks arrow-cpp broken here and plotly needs it, so the flake will not evaluate"
      return 1
      ;;
    *) note "unexpected system '$NFR_SYSTEM' for macOS"; return 1 ;;
  esac
}

t_macos_gui_session() {
  local m
  m=$(launchctl managername 2>/dev/null)
  echo "launchctl managername: $m"
  [ "$m" = Aqua ] || { note "no desktop session ($m, e.g. over SSH): GUI tests will be skipped"; return "$WARN"; }
  note "logged-in desktop session"
}

os_preflight() {
  run_test macos-version "macOS version"   t_macos_version
  run_test system        "Nix system"      t_macos_system
  run_test gui-session   "Desktop session" t_macos_gui_session
}

gui_available() {
  [ "$(launchctl managername 2>/dev/null)" = Aqua ]
}

main "$@"
