# Test suite

One command per platform builds the flake and checks everything it provides:
both dev shells, RAT-PAC, CRY, ROOT, a standalone Geant4 build, and the
visualizers.

```bash
tests/macos/run-tests.sh      # macOS, from Terminal
tests/linux/run-tests.sh      # Linux, from a terminal on the desktop
tests/windows/run-tests.sh    # Windows: inside the Ubuntu (WSL 2) terminal
```

Run it from a clone on the `unstable` branch, after README steps 1–2:

```bash
git clone -b unstable https://github.com/sandK-31/NixForRatpac.git
cd NixForRatpac
tests/linux/run-tests.sh
```

On WSL, clone under `~`, not `/mnt/c` (the script warns if you don't).

Start it from a plain terminal, not from inside `nix develop`: the suite
starts its own shells, and refuses to run inside one because the outer
shell's variables would leak into every test.

The first run compiles CRY and RAT-PAC and downloads Geant4, ROOT and the
Geant4 datasets: 20–60 minutes, printing progress every minute. After that a
full run takes about 10 minutes, most of it RAT-PAC's own physics tests
(`--quick` skips them).

## What you'll be asked

From a terminal, the suite ends by opening two windows and asking what you
saw: the RAT-PAC viewer, then a ROOT canvas. Look, close the window, answer
`y` or `n`; after an `n` it asks for one line on what was wrong, and that
line goes into the results. If no window appears at all, press Enter instead
of waiting; the suite closes the program and asks the question.

Ctrl-C stops the run but still writes the summary and the tarball for the
tests that finished.

These questions are the only check of what reaches your screen. The
automated GUI tests screenshot the window from inside the program, which
proves Qt and OpenGL render, but on WSL the picture can render perfectly and
still never reach Windows (the `[WARN: COPY MODE]` bug in the main README).

## Options

| Option | Effect |
| --- | --- |
| `--quick` | skip the `rattest` physics comparisons (~6 min) |
| `--no-gui` | skip everything that opens a window |
| `--no-interactive` | don't ask what you saw (automatic when not run from a terminal) |
| `--qpa xcb` | run the GUI tests with `QT_QPA_PLATFORM=xcb`, to try X11 where the shell would pick Wayland |

## Results

Each run writes `tests/results/<os>-<date>/` (ignored by git):

- `summary.txt`: one line per test
- `logs/<test>.log`: full output of each test; `logs/build-output.log` is the
  `nix build` log
- `screenshots/`: the Geant4 viewer and window for each driver, and the ROOT
  canvases
- `work/`: build trees and ROOT files, kept out of the tarball

and `tests/results/<os>-<date>.tar.gz` with the summary, logs and
screenshots. **If anything fails, send that tarball.**

The exit status is 0 only if nothing failed. Statuses:

| Status | Meaning |
| --- | --- |
| PASS | works |
| FAIL | broken |
| WARN | works, or might, but something needs a look (read the note) |
| XFAIL | fails on every machine for an upstream reason, not this environment |
| SKIP | not applicable here, or skipped by an option |

## What it checks

**Preflight** (every platform): Nix is installed, flakes are on, the checkout
is `unstable`. Then per platform:

- *macOS*: version, Nix system (`x86_64-darwin` fails: nixpkgs 26.05 marks
  `arrow-cpp` broken there and `plotly` needs it), whether there is a desktop
  session for the GUI tests.
- *Linux*: distribution; what desktop you have, which Qt platform (Wayland or
  X11) and OpenGL driver the GUI tests will use, and a warning for NVIDIA's
  proprietary driver, which the shell's Mesa can't use.
- *Windows*: that it's inside WSL, the WSL version, systemd, the repo isn't on
  `/mnt/c`, free space for `/nix`, WSLg is up, and `weston.log`'s
  `use_gfxredir` (0 means the COPY MODE bug is active and windows will be
  blank).

**Build**: the flake evaluates; `nix build` succeeds.

**RAT-PAC shell** (`nix develop`):

| Test | Checks |
| --- | --- |
| Versions | `rat` is RAT-PAC 4.4.0 from the store; Geant4 11.4.1; ROOT 6.40.00 |
| Environment variables | `RATROOT`, `RATSHARE`, `PYTHONPATH`, library and include paths (including `include/stlplus`), `CRY*`, `QT_QPA_PLATFORM`; on Linux also `GLIBC_TUNABLES` and, off NixOS, the Mesa OpenGL variables |
| Geant4 datasets | every `G4*DATA` variable points at a real directory |
| Qt platform plugin | the plugin `QT_QPA_PLATFORM` names is on `QT_PLUGIN_PATH` |
| Python packages | `numpy`, `plotly`, `particle`, `ROOT` import |
| `rat -h` | prints usage |
| 50 electrons → ntuple | RAT's `electron.mac` runs, events trigger, the ntuple reads back |
| DS file via rat module | a full `RAT::DS` file reads back through `import rat`, which needs RAT's ROOT dictionary |
| CRY: 10 cosmic showers | the `cry` generator runs; the primaries include muons |
| CRY with `CRYDATA` unset | `rat` falls back to the packaged CRY data instead of crashing |
| `find_package(Ratpac)` app | a downstream CMake project builds, links `Ratpac::RATPAC`, reads RATDB |
| Standalone CRY program | compiles against `$CRYINCLUDE`/`$CRYLIB` and generates showers |
| ROOT cling macro | cling runs a macro, fits a Gaussian, writes a PNG |
| `rattest` × 3 | RAT-PAC's own tests from `test/full`: `acrylic_attenuation` and `fitcentroid` compare fresh histograms with the committed `standard.root` (KS tests); `geoprint` is XFAIL, because its macro sets `DETECTOR geometry` and RAT now reads `geo_file` |

**Geant4-only shell** (`nix develop .#geant4`): no RAT-PAC in it but the CRY
variables are; a standalone Geant4 + Qt app builds with CMake; 20 × 100 MeV
electrons in water deposit a sensible energy.

**Visualization**:

| Test | Checks |
| --- | --- |
| Geant4 Qt viewer, default driver and OGLSQt | the standalone app opens the Qt GUI, draws a water cube and three showers, and screenshots the viewer from inside the event loop; passes if the picture has geometry and red/green track pixels |
| ROOT canvas on screen | ROOT gets a real graphics backend (not batch), draws, saves a PNG |
| RAT-PAC viewer | `rat -g` on the Validation detector stays up 10 s after its macro with no Qt errors; interactively, it stays open and asks what you saw |
| ROOT canvas, checked by you | interactive only |

## Layout

```
macos/run-tests.sh    entry point + macOS preflight
linux/run-tests.sh    entry point + Linux preflight
windows/run-tests.sh  entry point + WSL/WSLg preflight
common/harness.sh     flow, build, summary (runs outside Nix)
common/inner.sh       tests run inside the dev shells
common/gui.sh         visualization tests
common/lib.sh         run_test, timeouts, prompts
common/macros/        RAT macros: DS output, CRY, viewer
common/python/        ntuple / DS / ROOT-canvas checks (PyROOT)
common/root/          batch ROOT macro
common/g4app/         standalone Geant4 + Qt app (batch and screenshot modes)
common/ratapp/        find_package(Ratpac) app
common/cryapp/        standalone CRY program
```

Expected versions live at the top of `common/harness.sh`; bump them with
`flake.nix`.
