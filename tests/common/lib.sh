# Shared helpers for the NixForRatpac test suite. Sourced by harness.sh
# (outside Nix) and inner.sh (inside `nix develop`), so it has to work in the
# bash 3.2 that macOS ships: no associative arrays, no ${var,,}, no mapfile.

# Exit codes a test function can return, besides 0 (PASS) and anything else
# (FAIL).
SKIP=77   # not applicable here, or a precondition is missing
XFAIL=78  # known failure that is not this environment's fault
WARN=79   # works, but something deserves a look

if [ -t 1 ]; then
  C_PASS=$'\033[32m' C_FAIL=$'\033[31m' C_SKIP=$'\033[33m' C_HEAD=$'\033[1;36m'
  C_DIM=$'\033[2m' C_OFF=$'\033[0m'
else
  C_PASS='' C_FAIL='' C_SKIP='' C_HEAD='' C_DIM='' C_OFF=''
fi

section() {
  printf '\n%s== %s ==%s\n' "$C_HEAD" "$1" "$C_OFF"
}

# note <text> -- the one-line detail printed next to a test's status.
# The last note a test writes wins.
note() {
  echo "$*" >> "$NFR_NOTE"
  echo "note: $*"
}

# say <text> -- print to the terminal from inside a running test, whose own
# stdout goes to its log. harness.sh opens fd 3 on the terminal; inside
# `nix develop` it may not exist, hence the fallback to the log.
say() {
  : > "$NFR_LOGS/$NFR_ID.said"
  { printf '\n    %s' "$*" >&3; } 2>/dev/null || echo "$*"
}

# ask_yes_no <question> -- 0 for yes, 1 for no. Reads the terminal directly
# because run_test points stdin at /dev/null.
ask_yes_no() {
  local a
  : > "$NFR_LOGS/$NFR_ID.said"
  while :; do
    printf '\n    %s [y/n] ' "$1" > /dev/tty
    read -r a < /dev/tty || return 1
    case $a in
      y | Y | yes) echo "user answered yes: $1"; return 0 ;;
      n | N | no) echo "user answered no: $1"; return 1 ;;
    esac
  done
}

# ask_line <question> -- one line of free text from the user, on stdout.
ask_line() {
  local a
  printf '    %s ' "$1" > /dev/tty
  read -r a < /dev/tty
  echo "$a"
}

# run_test <id> <description> <command> [args...]
# Runs the command in a subshell with stdout+stderr in logs/<id>.log, prints a
# status line, and appends a row to results.tsv for the summary.
run_test() {
  local id=$1 desc=$2
  shift 2
  local log="$NFR_LOGS/$id.log"
  NFR_ID=$id
  NFR_NOTE="$NFR_LOGS/$id.note"
  : > "$NFR_NOTE"
  rm -f "$NFR_LOGS/$id.said"
  printf '  %-44s ' "$desc"
  local start=$SECONDS rc status colour detail
  ( "$@" ) > "$log" 2>&1 < /dev/null
  rc=$?
  # The test printed to the terminal mid-line; start a fresh status line.
  if [ -e "$NFR_LOGS/$id.said" ]; then
    printf '\n  %-44s ' "$desc"
    rm -f "$NFR_LOGS/$id.said"
  fi
  case $rc in
    0) status=PASS colour=$C_PASS ;;
    "$SKIP") status=SKIP colour=$C_SKIP ;;
    "$XFAIL") status=XFAIL colour=$C_SKIP ;;
    "$WARN") status=WARN colour=$C_SKIP ;;
    *) status=FAIL colour=$C_FAIL ;;
  esac
  detail=$(tail -n 1 "$NFR_NOTE" 2>/dev/null)
  printf '%s%-5s%s %s(%ss)%s %s\n' "$colour" "$status" "$C_OFF" \
    "$C_DIM" "$((SECONDS - start))" "$C_OFF" "$detail"
  if [ "$status" = FAIL ]; then
    printf '        %slog: %s%s\n' "$C_DIM" "${log#"$NFR_RESULTS"/}" "$C_OFF"
    tail -n 4 "$log" | sed 's/^/        | /'
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$status" "$id" "$desc" \
    "$((SECONDS - start))" "$detail" >> "$NFR_RESULTS/results.tsv"
  return 0
}

# with_timeout <seconds> <command> [args...]
# GNU timeout is not on macOS by default. Returns 124 on timeout.
with_timeout() {
  local secs=$1
  shift
  "$@" &
  local pid=$! waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$secs" ]; then
      echo "with_timeout: '$*' still running after ${secs}s, killing it"
      kill -TERM "$pid" 2>/dev/null
      sleep 3
      kill -KILL "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid"
}

# Last "CountProc: Total # of events N (M triggered events)" line of a rat log,
# as "N M".
rat_event_counts() {
  sed -n 's/.*CountProc: Total # of events \([0-9]*\) (\([0-9]*\) triggered.*/\1 \2/p' "$1" | tail -n 1
}
