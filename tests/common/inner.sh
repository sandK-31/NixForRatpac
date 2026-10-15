#!/usr/bin/env bash
# Tests that run inside a dev shell. harness.sh calls this as
#   nix develop <repo>         -c bash inner.sh ratpac
#   nix develop <repo>#geant4  -c bash inner.sh geant4
# with the NFR_* variables exported. Each test is a function; see lib.sh for
# the return-code convention.

set -u
COMMON=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$COMMON/lib.sh"

: "${NFR_OS:?}" "${NFR_RESULTS:?}" "${NFR_LOGS:?}" "${NFR_WORK:?}" "${NFR_ART:?}"
: "${NFR_EXPECT_RAT:?}" "${NFR_EXPECT_G4:?}" "${NFR_EXPECT_ROOT:?}"

if [ "$NFR_OS" = macos ]; then
  SO=dylib LIBVAR=DYLD_LIBRARY_PATH EXPECT_QPA=cocoa
else
  # The shell picks wayland when there is a compositor, xcb otherwise.
  SO=so LIBVAR=LD_LIBRARY_PATH EXPECT_QPA=xcb
  [ -n "${WAYLAND_DISPLAY:-}" ] && EXPECT_QPA=wayland
fi

# on_path <list> <entry> -- is <entry> one of the colon-separated <list>?
on_path() {
  case ":$1:" in *":$2:"*) return 0 ;; esac
  return 1
}

# check <label> <command...> -- one line per check in the log; failures are
# collected in $BAD for the note.
BAD=''
check() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok    $label"
  else
    echo "FAIL  $label"
    BAD="$BAD $label"
  fi
}

# ---------------------------------------------------------------- RAT-PAC shell

t_versions() {
  local rat g4 root
  rat=$(command -v rat) || { note "rat is not on PATH"; return 1; }
  g4=$(geant4-config --version)
  root=$(root-config --version)
  echo "rat: $rat"
  echo "Geant4: $g4"
  echo "ROOT: $root"
  case $rat in
    /nix/store/*-ratpac-two-"$NFR_EXPECT_RAT"/bin/rat) ;;
    *) note "rat is $rat, not ratpac-two-$NFR_EXPECT_RAT from the store"; return 1 ;;
  esac
  [ "$g4" = "$NFR_EXPECT_G4" ] || { note "Geant4 $g4, expected $NFR_EXPECT_G4"; return 1; }
  [ "$root" = "$NFR_EXPECT_ROOT" ] || { note "ROOT $root, expected $NFR_EXPECT_ROOT"; return 1; }
  note "RAT-PAC $NFR_EXPECT_RAT, Geant4 $g4, ROOT $root"
}

t_env() {
  env | grep -E '^(RAT|CRY|ROOT_INCLUDE|CPLUS_INCLUDE|QT_|G4VIS|DISPLAY|WAYLAND|PYTHONPATH|LD_LIBRARY|DYLD_LIBRARY|__EGL|LIBGL|GBM|GLIBC_TUNABLES)' | sort
  echo
  check RATROOT test -d "${RATROOT:-/nonexistent}/lib"
  check RATSHARE test -d "${RATSHARE:-/nonexistent}/ratdb"
  check PYTHONPATH on_path "${PYTHONPATH:-}" "${RATSHARE:-}/python"
  check "$LIBVAR" on_path "$(printenv "$LIBVAR")" "${RATROOT:-}/lib"
  check ROOT_INCLUDE_PATH on_path "${ROOT_INCLUDE_PATH:-}" "${RATROOT:-}/include"
  check ROOT_INCLUDE_PATH:stlplus on_path "${ROOT_INCLUDE_PATH:-}" "${RATROOT:-}/include/stlplus"
  check CRYLIB test -e "${CRYLIB:-/nonexistent}/libCRY.$SO"
  check CRYINCLUDE test -f "${CRYINCLUDE:-/nonexistent}/CRYGenerator.h"
  check CRYDATA test -f "${CRYDATA:-/nonexistent}/cosmics_0.data"
  check "QT_QPA_PLATFORM=$EXPECT_QPA" test "${QT_QPA_PLATFORM:-}" = "$EXPECT_QPA"
  local extra=''
  if [ "$NFR_OS" != macos ]; then
    check GLIBC_TUNABLES:optional_static_tls \
      test -n "$(echo "${GLIBC_TUNABLES:-}" | grep optional_static_tls)"
    # Off NixOS the shell supplies Mesa; on NixOS the system's driver is used.
    if [ ! -d /run/opengl-driver/lib ]; then
      check __EGL_VENDOR_LIBRARY_FILENAMES test -f "${__EGL_VENDOR_LIBRARY_FILENAMES:-/nonexistent}"
      check LIBGL_DRIVERS_PATH test -d "${LIBGL_DRIVERS_PATH:-/nonexistent}"
      extra=", Mesa for OpenGL"
    else
      extra=", NixOS OpenGL driver"
    fi
  fi
  [ -n "$BAD" ] && { note "wrong or missing:$BAD"; return 1; }
  note "RATROOT, RATSHARE, CRY*, include and library paths all set$extra"
}

t_g4data() {
  local n=0 missing='' var dir
  for var in $(env | sed -n 's/^\(G4[A-Z0-9]*DATA\)=.*/\1/p' | sort); do
    dir=$(printenv "$var")
    n=$((n + 1))
    if [ -d "$dir" ]; then echo "ok    $var=$dir"; else echo "FAIL  $var=$dir"; missing="$missing $var"; fi
  done
  [ -n "$missing" ] && { note "dataset directories missing:$missing"; return 1; }
  [ "$n" -ge 10 ] || { note "only $n G4*DATA variables set, expected at least 10"; return 1; }
  note "$n Geant4 dataset variables, all present"
}

# Qt finds the platform plugin named by QT_QPA_PLATFORM on QT_PLUGIN_PATH.
t_qt_plugin() {
  local want=${NFR_QPA_OVERRIDE:-$EXPECT_QPA} found='' all='' d f
  local IFS=:
  for d in ${QT_PLUGIN_PATH:-}; do
    for f in "$d"/platforms/*; do
      [ -e "$f" ] || continue
      echo "$f"
      all="$all $(basename "$f")"
      case $(basename "$f") in *"q$want"*) found=$f ;; esac
    done
  done
  unset IFS
  [ -n "$found" ] || { note "no '$want' platform plugin on QT_PLUGIN_PATH (have:$all)"; return 1; }
  note "$want plugin: $(basename "$found")"
}

t_python() {
  python - <<'EOF'
import numpy, plotly, particle, ROOT
print(f"PYTHON numpy={numpy.__version__} plotly={plotly.__version__} "
      f"particle={particle.__version__} ROOT={ROOT.gROOT.GetVersion()}")
EOF
  [ $? -eq 0 ] || { note "an import failed, see log"; return 1; }
  note "$(python -c 'import sys; print("Python", sys.version.split()[0])'): numpy, plotly, particle, ROOT import"
}

t_rat_help() {
  rat -h 2>&1 | tee "$NFR_WORK/rat-help.txt"
  grep -qi usage "$NFR_WORK/rat-help.txt" || { note "no usage text from rat -h"; return 1; }
  note "rat -h prints usage"
}

# run_rat <name> <events> <macro> [extra rat args] -- runs in $NFR_WORK/<name>,
# leaves the log in rat.out and prints "events triggered".
run_rat() {
  local name=$1 n=$2 mac=$3
  shift 3
  mkdir -p "$NFR_WORK/$name" && cd "$NFR_WORK/$name" || return 1
  rat -N "$n" -o "$name" "$@" "$mac" > rat.out 2>&1
  local rc=$?
  grep -v 'mat219\|AddProperty\|G4Exception\|issued by\|^\*\*\*\|^-------\|^$' rat.out | tail -n 25
  return $rc
}

t_rat_electron() {
  run_rat electron 50 "$RATSHARE/macros/examples/electron.mac" || { note "rat exited non-zero"; return 1; }
  set -- $(rat_event_counts rat.out)
  [ "${1:-0}" -eq 50 ] || { note "rat processed ${1:-0} of 50 events"; return 1; }
  [ "${2:-0}" -gt 0 ] || { note "50 events, none triggered"; return 1; }
  local out
  out=$(python "$COMMON/python/check_ntuple.py" electron.ntuple.root --min-entries 1 2>&1) \
    || { echo "$out"; note "ntuple check failed: $(echo "$out" | tail -n 1)"; return 1; }
  echo "$out"
  note "$2/50 triggered; $out"
}

# Writes the full RAT::DS (outroot) and reads it back through the rat Python
# module, which needs RAT's ROOT dictionary to parse its headers.
t_rat_ds() {
  run_rat ds 5 "$COMMON/macros/ds.mac" || { note "rat exited non-zero"; return 1; }
  local out
  out=$(python "$COMMON/python/check_ds.py" ds.root --events 5 --pdg 11 2>&1)
  local rc=$?
  echo "$out"
  [ $rc -eq 0 ] || { note "$(echo "$out" | grep -m1 -E 'DS |error|Error' || echo 'DS read failed, see log')"; return 1; }
  note "$(echo "$out" | grep '^DS ')"
}

t_cry() {
  run_rat cry 10 "$COMMON/macros/cry.mac" || { note "rat exited non-zero"; return 1; }
  grep -q 'CRY::CRYSetup: Setting altitude' rat.out || { note "CRY never configured itself"; return 1; }
  local out
  out=$(python "$COMMON/python/check_ntuple.py" cry.ntuple.root --min-entries 10 --require-pdg 13,-13 2>&1) \
    || { echo "$out"; note "no cosmic muons: $(echo "$out" | tail -n 1)"; return 1; }
  echo "$out"
  note "$out"
}

# rat carries a CRYDATA default in its wrapper, so CRY must work without it.
t_cry_default_data() {
  mkdir -p "$NFR_WORK/cry-nodata" && cd "$NFR_WORK/cry-nodata" || return 1
  env -u CRYDATA rat -N 1 -o crynodata "$COMMON/macros/cry.mac" > rat.out 2>&1
  local rc=$?
  tail -n 15 rat.out
  [ $rc -eq 0 ] || { note "rat exited $rc with CRYDATA unset"; return 1; }
  set -- $(rat_event_counts rat.out)
  [ "${1:-0}" -eq 1 ] || { note "event did not run with CRYDATA unset"; return 1; }
  note "1 CRY event with CRYDATA unset (wrapper default)"
}

t_ratpac_cmake() {
  local b="$NFR_WORK/ratapp-build"
  cmake -S "$COMMON/ratapp" -B "$b" -DCMAKE_BUILD_TYPE=Release || { note "cmake configure failed (find_package(Ratpac))"; return 1; }
  cmake --build "$b" || { note "build failed"; return 1; }
  local out
  out=$("$b/ratapp" 2>&1)
  local rc=$?
  echo "$out"
  [ $rc -eq 0 ] || { note "ratapp exited $rc"; return 1; }
  note "$(echo "$out" | grep '^RATAPP')"
}

t_cry_standalone() {
  c++ -std=c++17 -O2 "$COMMON/cryapp/cryapp.cc" -I"$CRYINCLUDE" -L"$CRYLIB" -lCRY \
    -o "$NFR_WORK/cryapp" || { note "compile/link against \$CRYINCLUDE/\$CRYLIB failed"; return 1; }
  local out
  out=$("$NFR_WORK/cryapp" 300 2>&1)
  local rc=$?
  echo "$out"
  [ $rc -eq 0 ] || { note "$(echo "$out" | tail -n 1)"; return 1; }
  note "$(echo "$out" | grep '^CRYAPP')"
}

t_root_cling() {
  cd "$NFR_WORK" || return 1
  local out
  out=$(root -l -b -q "$COMMON/root/fit_gaus.C(\"$NFR_ART/root-batch-fit.png\")" 2>&1)
  echo "$out"
  local line
  line=$(echo "$out" | grep '^FIT ')
  [ -n "$line" ] || { note "macro produced no fit"; return 1; }
  [ -s "$NFR_ART/root-batch-fit.png" ] || { note "no PNG written (libASImage?)"; return 1; }
  echo "$line" | grep -q 'ok=1' || { note "$line"; return 1; }
  note "$line, PNG written"
}

# RAT-PAC's own physics tests, from test/full in the pinned source. Each one
# compares fresh histograms against a committed standard.root with KS tests.
t_rattest() {
  local name=$1
  [ "${NFR_QUICK:-0}" = 1 ] && { note "skipped (--quick)"; return "$SKIP"; }
  local src="${NFR_RATPAC_SRC:-}/test/full/$name"
  [ -d "$src" ] || { note "RAT-PAC source not found at '$src'"; return 1; }
  mkdir -p "$NFR_WORK/rattest" && rm -rf "${NFR_WORK:?}/rattest/$name" \
    && cp -R "$src" "$NFR_WORK/rattest/" && chmod -R u+w "$NFR_WORK/rattest/$name" \
    && cd "$NFR_WORK/rattest" || return 1
  rattest -t "$name" > rattest-"$name".out 2>&1
  local rc=$?
  sed 's/\x1b\[[0-9;]*m//g' rattest-"$name".out | grep -E 'Comparing|SUCCESS|FAILURE|Error|error|Traceback' | grep -v 'mat219'
  local ok bad
  ok=$(grep -c 'SUCCESS' rattest-"$name".out)
  bad=$(grep -c 'FAILURE' rattest-"$name".out)
  [ "$bad" -eq 0 ] && [ "$ok" -gt 0 ] && [ $rc -eq 0 ] \
    || { note "$ok KS comparisons passed, $bad failed (rattest exit $rc)"; return 1; }
  note "$ok/$ok KS comparisons against standard.root pass"
}

t_rattest_geoprint() {
  note "not run: upstream macro sets DETECTOR geometry, RAT now reads geo_file, so rat dies on any machine"
  return "$XFAIL"
}

# ----------------------------------------------------------- Geant4-only shell

t_g4_shell() {
  local g4 root
  g4=$(geant4-config --version)
  root=$(root-config --version)
  echo "Geant4 $g4, ROOT $root, RATROOT=${RATROOT:-unset}, rat=$(command -v rat || echo none)"
  [ -z "${RATROOT:-}" ] || { note "RATROOT is set in the RAT-PAC-free shell"; return 1; }
  ! command -v rat >/dev/null || { note "rat is on PATH in the RAT-PAC-free shell"; return 1; }
  [ "$g4" = "$NFR_EXPECT_G4" ] && [ "$root" = "$NFR_EXPECT_ROOT" ] \
    || { note "Geant4 $g4 / ROOT $root, expected $NFR_EXPECT_G4 / $NFR_EXPECT_ROOT"; return 1; }
  [ -f "${CRYDATA:-/nonexistent}/cosmics_0.data" ] || { note "CRY variables missing"; return 1; }
  note "Geant4 $g4 + ROOT $root, no RAT-PAC, CRY variables set"
}

t_g4_build() {
  local b="$NFR_WORK/g4app-build"
  cmake -S "$COMMON/g4app" -B "$b" -DCMAKE_BUILD_TYPE=Release || { note "cmake configure failed (find_package(Geant4))"; return 1; }
  cmake --build "$b" -j 4 || { note "build failed"; return 1; }
  note "standalone Geant4 + Qt app built with CMake"
}

t_g4_batch() {
  local app="$NFR_WORK/g4app-build/g4app"
  [ -x "$app" ] || { note "g4app was not built"; return "$SKIP"; }
  cd "$NFR_WORK" || return 1
  local out
  out=$("$app" batch 20 2>&1)
  local rc=$?
  echo "$out" | tail -n 20
  [ $rc -eq 0 ] || { note "g4app batch exited $rc"; return 1; }
  note "$(echo "$out" | grep '^BATCH')"
}

# ------------------------------------------------------------------------ main

# Ctrl-C: stop after the running test instead of finishing the group (rat
# catches SIGINT and exits normally, so bash would carry on). The harness
# then writes the summary.
trap 'exit 130' INT

case ${1:-} in
  ratpac)
    run_test versions        "Versions"                        t_versions
    run_test env             "Environment variables"           t_env
    run_test g4data          "Geant4 datasets"                 t_g4data
    run_test qt-plugin       "Qt platform plugin"              t_qt_plugin
    run_test python          "Python packages"                 t_python
    run_test rat-help        "rat -h"                          t_rat_help
    run_test rat-electron    "RAT: 50 electrons -> ntuple"     t_rat_electron
    run_test rat-ds          "RAT: DS file via rat module"     t_rat_ds
    run_test cry             "CRY: 10 cosmic showers"          t_cry
    run_test cry-nodata      "CRY: runs with CRYDATA unset"    t_cry_default_data
    run_test ratpac-cmake    "find_package(Ratpac) app"        t_ratpac_cmake
    run_test cry-standalone  "Standalone CRY program"          t_cry_standalone
    run_test root-cling      "ROOT: cling macro + PNG"         t_root_cling
    run_test rattest-acrylic "rattest acrylic_attenuation"     t_rattest acrylic_attenuation
    run_test rattest-fitcentroid "rattest fitcentroid"         t_rattest fitcentroid
    run_test rattest-geoprint "rattest geoprint"               t_rattest_geoprint
    ;;
  geant4)
    run_test g4-shell        "Shell contents"                  t_g4_shell
    run_test g4-build        "Build Geant4 app (CMake)"        t_g4_build
    run_test g4-batch        "Geant4: 20 x 100 MeV e- in water" t_g4_batch
    ;;
  *)
    echo "usage: inner.sh ratpac|geant4" >&2
    exit 2
    ;;
esac
