# Visualization tests, sourced by harness.sh. Unlike inner.sh these run
# outside the dev shell and start each GUI program through `nix develop`, so
# they can watch the process, screenshot it, and kill it when done.
#
# The automated checks prove Qt and OpenGL render *inside* the machine. They
# cannot see the screen itself: under WSLg's COPY MODE bug, for one, the
# picture renders fine and never reaches Windows. That is what the
# interactive checks (on by default in a terminal) are for.

# in_shell <"" | "#geant4"> <command...> -- run a command in a dev shell,
# with QT_QPA_PLATFORM replaced if --qpa was given.
in_shell() {
  local ref="$NFR_REPO$1"
  shift
  if [ -n "${NFR_QPA_OVERRIDE:-}" ]; then
    nixc develop "$ref" -c env QT_QPA_PLATFORM="$NFR_QPA_OVERRIDE" "$@"
  else
    nixc develop "$ref" -c "$@"
  fi
}

# g_g4_viewer <driver|default> -- the standalone Geant4 app opens its Qt GUI,
# screenshots the viewer from inside the event loop, and checks the picture.
g_g4_viewer() {
  local driver=$1 app="$NFR_WORK/g4app-build/g4app"
  [ -x "$app" ] || { note "g4app was not built (see the Geant4-only shell tests)"; return "$SKIP"; }
  cd "$NFR_WORK" || return 1
  with_timeout 240 in_shell "#geant4" "$app" vis "$driver" \
    "$NFR_ART/g4-viewer-$driver.png" "$NFR_ART/g4-window-$driver.png"
  local rc=$?
  [ $rc -eq 124 ] && { note "timed out: the Qt window never came up or never painted"; return 1; }
  local line
  line=$(grep '^VIEWER' "$NFR_LOGS/$NFR_ID.log" | tail -n 1)
  [ $rc -eq 0 ] || { note "${line:-g4app exited $rc before taking a screenshot}"; return 1; }
  note "${line#VIEWER }"
}

g_root_canvas() {
  cd "$NFR_WORK" || return 1
  with_timeout 120 in_shell "" python "$NFR_COMMON/python/root_canvas.py" \
    "$NFR_ART/root-canvas.png" --hold 3
  local rc=$?
  local line
  line=$(grep '^ROOT_GUI' "$NFR_LOGS/$NFR_ID.log" | head -n 1)
  [ $rc -eq 0 ] || { note "${line:-root_canvas.py exited $rc}"; return 1; }
  [ -s "$NFR_ART/root-canvas.png" ] || { note "no PNG saved from the canvas"; return 1; }
  note "${line#ROOT_GUI }, PNG saved"
}

g_root_canvas_look() {
  cd "$NFR_WORK" || return 1
  local png="$NFR_ART/root-canvas-look.png"
  say "A ROOT canvas with a fitted Gaussian histogram is opening. Look at it, then close its window."
  say "(If no window appears within a minute, press Enter.)"
  in_shell "" python "$NFR_COMMON/python/root_canvas.py" "$png" --wait-close &
  wait_for_close $! "$png" 660
  if ask_yes_no "Did the ROOT canvas show a histogram with a red fit curve?"; then
    note "you saw the canvas"
  else
    note "you reported: $(ask_line 'What did you see instead (one line)?')"
    return 1
  fi
}

# stop_matching <pattern> -- signal the GUI program itself, found by a path
# unique to this run on its command line: the PID we hold is `nix develop`'s.
stop_matching() {
  pkill -TERM -f "$1" 2>/dev/null
  local i=0
  while pgrep -f "$1" >/dev/null 2>&1 && [ $i -lt 10 ]; do sleep 1; i=$((i + 1)); done
  pkill -KILL -f "$1" 2>/dev/null
}

# wait_for_close <pid> <pattern> <max s> -- wait for the user to close the
# window, or to press Enter if none appeared (an invisible window can't be
# closed), then make sure the program is gone.
wait_for_close() {
  local pid=$1 pattern=$2 end=$((SECONDS + $3)) t
  while kill -0 "$pid" 2>/dev/null && [ $SECONDS -lt $end ]; do
    t=$SECONDS
    read -r -t 1 _ 2>/dev/null < /dev/tty && break
    # read failed at once (no terminal): wait the second out instead.
    [ $SECONDS -eq "$t" ] && sleep 1
  done
  kill -0 "$pid" 2>/dev/null && stop_matching "$pattern"
  wait "$pid" 2>/dev/null
}

# rat -g on the Validation detector. Passes once the window has been up for
# 10 s after the macro finished without rat dying or Qt complaining; in
# interactive mode it then stays up until you close it and asks what you saw.
g_rat_viewer() {
  local dir="$NFR_WORK/rat-vis"
  mkdir -p "$dir" && cd "$dir" && cp "$NFR_COMMON/macros/rat_vis.mac" . || return 1
  local mac="$dir/rat_vis.mac"
  in_shell "" rat -g "$mac" > rat.out 2>&1 &
  local pid=$! waited=0
  # Once the Qt session exists, G4cout goes to the viewer's console, not
  # stdout; RAT's own rat.<host>.<pid>.log still gets all of it.
  ratlog() { cat rat.out rat.*.log 2>/dev/null; }
  until ratlog | grep -q NFR_VIS_MACRO_DONE; do
    # A failed command stops the macro but leaves rat -g sitting at its prompt.
    if ratlog | grep -q 'Batch is interrupted'; then
      ratlog | grep -B 12 'Batch is interrupted' | grep -v '^$'
      stop_matching "$mac"
      note "macro aborted: $(ratlog | grep -m1 'Illegal parameter\|command not found\|is not listed')"
      return 1
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      tail -n 30 rat.out
      note "rat -g exited before the macro finished"
      return 1
    fi
    if [ $waited -ge 300 ]; then
      stop_matching "$mac"
      note "macro still not done after 300 s"
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  sleep 10
  if ! kill -0 "$pid" 2>/dev/null; then
    tail -n 30 rat.out
    note "rat -g died after the macro finished (Qt session failed?)"
    return 1
  fi
  local qt_errors
  qt_errors=$(grep -iE 'qt\.qpa|could not (load|connect|find)|failed to create|GLX|EGL_|segmentation' rat.out \
    | grep -v 'qt\.qpa\.fonts' | head -n 3)
  ratlog | grep -E 'CountProc|NFR_VIS|kept for refreshing|vis/open|OGLSQt' | tail -n 10
  [ -n "$qt_errors" ] && echo "Qt/GL messages: $qt_errors"

  if [ "${NFR_INTERACTIVE:-0}" != 1 ]; then
    stop_matching "$mac"
    [ -n "$qt_errors" ] && { note "viewer stayed up, but: $(echo "$qt_errors" | head -n 1)"; return "$WARN"; }
    note "viewer up for 10 s after the macro, no Qt errors"
    return 0
  fi

  say "The RAT-PAC viewer is open: the Validation detector, cut in half, with three"
  say "electron tracks. Look at it (rotate it if you like), then close the window."
  say "(No window anywhere, not even in the taskbar? Press Enter.)"
  wait_for_close "$pid" "$mac" 900
  if ask_yes_no "Did the window show the detector geometry and the electron tracks?"; then
    note "you saw the detector and tracks${qt_errors:+ (log has Qt/GL messages)}"
  else
    note "you reported: $(ask_line 'What did you see instead (one line)?')"
    return 1
  fi
}

run_gui_tests() {
  run_test g4-viewer-default "Geant4 Qt viewer, default driver"  g_g4_viewer default
  run_test g4-viewer-ogl     "Geant4 Qt viewer, OGLSQt"          g_g4_viewer OGLSQt
  run_test root-canvas       "ROOT canvas on screen"             g_root_canvas
  run_test rat-viewer        "RAT-PAC viewer (rat -g)"           g_rat_viewer
  if [ "${NFR_INTERACTIVE:-0}" = 1 ]; then
    run_test root-canvas-look "ROOT canvas, checked by you"      g_root_canvas_look
  fi
}
