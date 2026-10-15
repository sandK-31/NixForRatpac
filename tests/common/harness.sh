# Driver for the NixForRatpac test suite. Sourced by tests/<os>/run-tests.sh,
# which sets NFR_OS and defines os_preflight and gui_available, then calls
# main "$@". Runs outside Nix: under macOS that means bash 3.2.

# What the unstable branch pins. Bump these together with flake.nix.
NFR_EXPECT_RAT=4.4.0
NFR_EXPECT_G4=11.4.1
NFR_EXPECT_ROOT=6.40.00

NFR_COMMON=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
NFR_REPO=$(cd "$NFR_COMMON/../.." && pwd)
. "$NFR_COMMON/lib.sh"
. "$NFR_COMMON/gui.sh"

# Every nix call carries the flags itself, so a machine that skipped README
# step 2 still runs the suite (t_flakes reports it).
nixc() {
  nix --extra-experimental-features 'nix-command flakes' "$@"
}

usage() {
  cat <<EOF
usage: tests/$NFR_OS/run-tests.sh [options]

Builds the flake (compiling CRY and RAT-PAC on the first run), then tests
both dev shells, RAT-PAC, CRY, ROOT, Geant4 and the visualizers.

  --quick           skip RAT-PAC's rattest physics comparisons (~6 min)
  --no-gui          skip everything that opens a window
  --no-interactive  don't ask you to look at windows (default when not
                    run from a terminal)
  --qpa <plugin>    run the GUI tests with QT_QPA_PLATFORM=<plugin>,
                    e.g. xcb to try X11 instead of Wayland
  -h, --help        this text

Results go to tests/results/$NFR_OS-<date>/, plus a .tar.gz of the logs and
screenshots next to it.
EOF
}

# ------------------------------------------------------------------ preflight

t_nix() {
  command -v nix || { note "nix not found: README step 1, or open a new terminal"; return 1; }
  note "$(nix --version)"
}

t_flakes() {
  local features
  features=$(nix config show experimental-features 2>/dev/null || nix show-config 2>/dev/null | sed -n 's/^experimental-features = //p')
  echo "experimental-features: $features"
  case " $features " in
    *" flakes "*) case " $features " in *" nix-command "*) note "flakes + nix-command on"; return 0 ;; esac ;;
  esac
  note "flakes not enabled permanently (README step 2); the suite passes the flags itself"
  return "$WARN"
}

t_repo() {
  local branch sha dirty=''
  branch=$(git -C "$NFR_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null) || { note "not a git checkout"; return "$WARN"; }
  sha=$(git -C "$NFR_REPO" rev-parse --short HEAD)
  [ -n "$(git -C "$NFR_REPO" status --porcelain -- flake.nix flake.lock)" ] && dirty=', flake.nix/flake.lock modified'
  git -C "$NFR_REPO" log -1 --format='%h %s (%cr)'
  [ "$branch" = unstable ] || { note "on '$branch' @ $sha; this suite expects 'unstable'$dirty"; return "$WARN"; }
  note "unstable @ $sha$dirty"
}

t_flake_eval() {
  nixc flake check --no-build "$NFR_REPO" || { note "flake does not evaluate on $NFR_SYSTEM"; return 1; }
  note "packages and both dev shells evaluate on $NFR_SYSTEM"
}

# nix build, with a progress line every minute: on a fresh machine this
# downloads Geant4, ROOT and the datasets and compiles CRY and RAT-PAC.
t_build() {
  local out="$NFR_LOGS/build-output.log" start=$SECONDS next=60
  nixc build "$NFR_REPO#default" --no-link --print-out-paths -L > "$out" 2>&1 &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    sleep 2
    if [ $((SECONDS - start)) -ge $next ]; then
      say "... $(( (SECONDS - start) / 60 )) min: $(grep -v '^warning' "$out" | tail -n 1 | cut -c1-90)"
      next=$((next + 60))
    fi
  done
  wait "$pid"
  local rc=$?
  tail -n 30 "$out"
  [ $rc -eq 0 ] || { note "nix build failed, see logs/build-output.log"; return 1; }
  note "$(grep '^/nix/store' "$out" | tail -n 1)"
}

# --------------------------------------------------------------------- shells

# run_shell <"" | "#geant4"> <group> -- inner.sh inside a dev shell. If the
# shell itself fails to start, no rows appear; record that as a failure.
t_shell_failed() {
  tail -n 20 "$NFR_LOGS/nix-develop-$1.log"
  note "nix develop failed to start, see logs/nix-develop-$1.log"
  return 1
}

run_shell() {
  local ref=$1 group=$2 before after
  before=$(wc -l < "$NFR_RESULTS/results.tsv")
  nixc develop "$NFR_REPO$ref" -c bash "$NFR_COMMON/inner.sh" "$group" 2>> "$NFR_LOGS/nix-develop-$group.log"
  after=$(wc -l < "$NFR_RESULTS/results.tsv")
  [ "$after" -eq "$before" ] && run_test "shell-$group" "nix develop .$ref" t_shell_failed "$group"
  return 0
}

# -------------------------------------------------------------------- summary

count_status() {
  awk -F'\t' -v s="$1" '$1 == s' "$NFR_RESULTS/results.tsv" | wc -l | tr -d ' '
}

summarise() {
  local f="$NFR_RESULTS/summary.txt" s n
  {
    echo "NixForRatpac test suite: $NFR_OS ($NFR_SYSTEM)"
    echo "Run:    $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Host:   $(uname -srm)"
    echo "Repo:   $(git -C "$NFR_REPO" log -1 --format='%h %s' 2>/dev/null)"
    echo "Flags:  quick=$NFR_QUICK gui=$NFR_GUI interactive=$NFR_INTERACTIVE qpa=${NFR_QPA_OVERRIDE:-default}"
    echo
    awk -F'\t' '{ printf "%-5s  %-22s %s\n", $1, $2, $5 }' "$NFR_RESULTS/results.tsv"
  } > "$f"

  section Summary
  for s in PASS FAIL WARN XFAIL SKIP; do
    n=$(count_status "$s")
    [ "$n" -gt 0 ] && printf '  %-6s %s\n' "$s" "$n"
  done
  NFR_FAILS=$(count_status FAIL)
  if [ "$NFR_FAILS" -gt 0 ]; then
    echo
    echo "  Failed:"
    awk -F'\t' '$1 == "FAIL" { printf "    %-22s %s\n", $2, $5 }' "$NFR_RESULTS/results.tsv"
  fi

  local base
  base=$(basename "$NFR_RESULTS")
  tar -czf "$NFR_RESULTS.tar.gz" -C "$(dirname "$NFR_RESULTS")" --exclude "$base/work" "$base" 2>/dev/null
  echo
  echo "  Summary:     ${NFR_RESULTS#"$NFR_REPO"/}/summary.txt"
  echo "  Screenshots: ${NFR_ART#"$NFR_REPO"/}/"
  echo "  To share:    ${NFR_RESULTS#"$NFR_REPO"/}.tar.gz (logs + screenshots)"
}

# ----------------------------------------------------------------------- main

main() {
  NFR_QUICK=0 NFR_GUI=1 NFR_INTERACTIVE=0 NFR_QPA_OVERRIDE=''
  [ -t 0 ] && [ -t 1 ] && NFR_INTERACTIVE=1
  while [ $# -gt 0 ]; do
    case $1 in
      --quick) NFR_QUICK=1 ;;
      --no-gui) NFR_GUI=0 ;;
      --no-interactive) NFR_INTERACTIVE=0 ;;
      --qpa) NFR_QPA_OVERRIDE=${2:?--qpa needs a plugin name}; shift ;;
      -h | --help) usage; exit 0 ;;
      *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
  done

  # Each test starts its own `nix develop`; started from inside one, the
  # outer shell's variables (RATROOT, PATH, include paths) leak into every
  # test, the Geant4-only shell included.
  if [ -n "${IN_NIX_SHELL:-}" ]; then
    echo "This terminal is inside 'nix develop'. Type 'exit', then run the suite again." >&2
    exit 2
  fi

  NFR_RESULTS="$NFR_REPO/tests/results/$NFR_OS-$(date +%Y%m%d-%H%M%S)"
  NFR_LOGS="$NFR_RESULTS/logs" NFR_WORK="$NFR_RESULTS/work" NFR_ART="$NFR_RESULTS/screenshots"
  mkdir -p "$NFR_LOGS" "$NFR_WORK" "$NFR_ART" || exit 1
  : > "$NFR_RESULTS/results.tsv"
  export NFR_OS NFR_REPO NFR_COMMON NFR_RESULTS NFR_LOGS NFR_WORK NFR_ART \
    NFR_QUICK NFR_INTERACTIVE NFR_QPA_OVERRIDE \
    NFR_EXPECT_RAT NFR_EXPECT_G4 NFR_EXPECT_ROOT
  exec 3>&1
  # Ctrl-C still leaves a summary and a tarball of what ran.
  trap 'echo; echo "  Interrupted."; summarise; exit 130' INT

  printf '%sNixForRatpac test suite (%s)%s\n' "$C_HEAD" "$NFR_OS" "$C_OFF"
  echo "Repo:    $NFR_REPO"
  echo "Results: ${NFR_RESULTS#"$NFR_REPO"/}/"

  section Preflight
  run_test nix "Nix installed" t_nix
  if ! command -v nix >/dev/null; then summarise; exit 1; fi
  NFR_SYSTEM=$(nixc eval --impure --raw --expr builtins.currentSystem 2>/dev/null)
  export NFR_SYSTEM
  run_test flakes "Flakes enabled" t_flakes
  run_test repo "Git checkout" t_repo
  os_preflight

  section "Build (the first run compiles CRY and RAT-PAC: 20-60 min)"
  run_test flake-eval "Flake evaluates" t_flake_eval
  run_test build "nix build" t_build
  if awk -F'\t' '$1 == "FAIL" && $2 == "build" { found = 1 } END { exit !found }' "$NFR_RESULTS/results.tsv"; then
    echo "  Build failed; nothing else can run."
    summarise
    exit 1
  fi
  NFR_RATPAC_SRC=$(nixc eval --raw "$NFR_REPO#packages.$NFR_SYSTEM.default.src" 2>/dev/null)
  export NFR_RATPAC_SRC

  section "RAT-PAC shell: nix develop"
  run_shell "" ratpac

  section "Geant4-only shell: nix develop .#geant4"
  run_shell "#geant4" geant4

  section "Visualization"
  if [ "$NFR_GUI" != 1 ]; then
    echo "  skipped (--no-gui)"
  elif ! gui_available; then
    echo "  skipped: no display here (see the preflight notes)"
  else
    [ "$NFR_INTERACTIVE" = 1 ] && echo "  Windows will open; some tests ask what you saw."
    run_gui_tests
  fi

  summarise
  [ "$NFR_FAILS" -eq 0 ]
}
