# NixForRatpac

A single [Nix flake](https://nixos.wiki/wiki/Flakes) that gives you a reproducible
**RAT-PAC 2 + Geant4 + ROOT** development environment with one command:

```bash
nix develop
```

No `apt`/`brew` packages to install, no manual CMake builds, no `LD_LIBRARY_PATH`
archaeology. Works on Apple Silicon Macs and Linux, and on Windows through
WSL 2 — see [Step 1](#windows-wsl-2). Intel Macs need the previous version
(below).

> ### Upgrading from the previous version
>
> As of 2026-10-16 this environment is on nixpkgs `nixos-26.05` (Geant4 11.4.1,
> ROOT 6.40.00) and RAT-PAC **4.4.0**, up from RAT-PAC 3.x, Geant4 11.3.2 and
> ROOT 6.36.04. The full test suite passes on Apple Silicon macOS, Linux and
> Windows (WSL).
> If you already use this repo, after `git pull`:
>
> - **The first `nix develop` rebuilds the environment**, so budget time for it.
> - **`RATEvent` is gone.** If your experiment's `CMakeLists.txt` links
>   `RATEvent`, drop it and link `RATPAC` alone — see
>   [RAT-PAC 4.3.0 → 4.4.0](#rat-pac-430--440-libratevent-is-gone).
> - **Optical timing can differ from earlier runs** (RAT-PAC #447). Check before
>   mixing new results with old ones.
> - **Not tested on Intel Macs, and not supported there.** This version has
>   never been run on an Intel Mac. It also cannot be: nixpkgs 26.05 marks
>   `arrow-cpp` broken on `x86_64-darwin`, and `plotly` needs it, so neither
>   shell evaluates there. Intel Mac users should stay on `ratpac-3` (below).
>
> The previous environment is kept as the tag `ratpac-3`. To stay on it, run
> `git checkout ratpac-3` in your clone, or
> `nix develop github:sandK-31/NixForRatpac/ratpac-3` without one. See
> [What changed in this version](#what-changed-in-this-version) for details.

> Originally written by [Ethan W. Todd](https://github.com/ewtodd), adapted by
> [Sander Katz](https://github.com/sandK-31).

**What you get inside the shell**

| Component | Version (as pinned) |
| --- | --- |
| RAT-PAC 2 | `rat-pac/ratpac-two` @ `4.4.0` (2026-10-11) |
| Geant4 | 11.4.1, built with Qt6 visualization enabled (and, on Linux, the `global-dynamic` TLS model so Python can load it) |
| ROOT | 6.40.00 |
| Geant4 datasets | G4NDL, G4EMLOW, G4PhotonEvaporation, G4RadioactiveDecay, … |
| CRY | 1.7 (LLNL cosmic-ray showers), built into RAT-PAC as the `cry` generator |
| Python | 3.x with `numpy`, `ROOT`, `plotly`, `particle` |

**Don't need RAT-PAC?** There's a second shell with everything above *except*
RAT-PAC — see [Step 4](#without-rat-pac-geant4--root-only):

```bash
nix develop .#geant4
```

---

## Step 1 — Install Nix

Download page: **<https://nixos.org/download/>**

### macOS

> **Intel Macs:** this version is not tested on Intel Macs and does not
> evaluate there. Install Nix as below, then use the `ratpac-3` tag — see
> [Upgrading from the previous version](#upgrading-from-the-previous-version).

Nix on macOS is always a *multi-user* (daemon) install. Run the official installer:

```bash
curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install | sh
```

It will ask for your password (it creates a separate `/nix` APFS volume and a
`nixbld` user group). Answer `y` when it asks to proceed.

### Linux

```bash
curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install | sh -s -- --daemon
```

### Windows (WSL 2)

There is no native Windows build — Nix needs a POSIX system and a `/nix` store.
On Windows you install **WSL 2** and then follow the *Linux* path inside it.
Everything after this point (`nix develop`, `rat`, ROOT, the Geant4 Qt viewer)
then behaves exactly as it does on a native Linux box, and GUI windows appear as
ordinary Windows windows courtesy of WSLg.

You need Windows 11, or Windows 10 21H2+ with WSLg, and roughly **40 GB free** on
the drive holding the WSL disk — `/nix/store` gets large.

**1. Install WSL 2 and Ubuntu.** In an *administrator* PowerShell:

```powershell
wsl --install -d Ubuntu
```

Reboot if it asks, then launch **Ubuntu** from the Start menu and create your
UNIX username and password when prompted.

**2. Make sure WSL itself is current.** WSLg — the component that draws Qt
windows — ships with WSL, not with Ubuntu:

```powershell
wsl --update
wsl --version
```

**3. Turn on systemd.** The multi-user Nix install expects systemd, which WSL
does not start by default. Inside Ubuntu:

```bash
sudo tee -a /etc/wsl.conf >/dev/null <<'EOF'
[boot]
systemd=true
EOF
```

Back in PowerShell, restart the distro so it takes effect:

```powershell
wsl --shutdown
```

Reopen Ubuntu and check:

```bash
systemctl is-system-running    # "running" or "degraded" — either is fine
```

**4. Install Nix** with the Linux command above, run from inside Ubuntu:

```bash
curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install | sh -s -- --daemon
```

> If you can't enable systemd (locked-down machine, ancient WSL), the single-user
> install works too: `curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install | sh -s -- --no-daemon`.
> It puts the store under your user instead of a daemon, and everything in this
> README still applies.

From here on **everything happens inside the Ubuntu shell.** Steps 2–5 are the
Linux instructions verbatim; `nix`, `rat` and `root` do not exist on the Windows
side and PowerShell cannot see them.

> **If a window opens as a blank taskbar entry with `[WARN: COPY MODE]` in its
> title** — the digitizer is the usual victim — that's a known WSLg bug, not
> anything you did. The fix is two lines: see
> [Troubleshooting](#troubleshooting).

### After installing (all platforms)

**Open a new terminal window.** The installer appends a hook to `/etc/zshrc`
(macOS) or `/etc/bash.bashrc` (Linux) that puts `nix` on your `PATH`, and it only
takes effect in shells started afterwards.

Verify:

```bash
nix --version
# nix (Nix) 2.33.3
```

If you get `command not found: nix`, source the profile manually:

```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

> **Alternative:** the [Determinate Systems installer](https://determinate.systems/nix)
> (`curl -fsSL https://install.determinate.systems/nix | sh -s -- install`) enables
> flakes automatically, survives macOS upgrades, and has a clean uninstaller. If you
> use it you can **skip Step 2 entirely**.

---

## Step 2 — Enable flakes permanently

Flakes and the `nix` CLI are still gated behind experimental feature flags. You can
pass them per-command:

```bash
nix --extra-experimental-features 'nix-command flakes' develop
```

…but that gets old fast. To make it permanent you have to **edit a config file** —
there is no `nix config set` command for this.

There are two files, and which one you edit matters:

| File | Applies to | Needs `sudo`? | Needs daemon restart? |
| --- | --- | --- | --- |
| `~/.config/nix/nix.conf` | just you | no | no |
| `/etc/nix/nix.conf` | all users on the machine | yes | **yes, on macOS** |

### Option A — user-only (simplest, no `sudo`)

```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

That's it — no restart needed. Open a new shell and go to Step 3.

### Option B — system-wide (macOS)

`/etc/nix/nix.conf` already exists and contains a `build-users-group = nixbld` line
that the daemon needs. **Append to it, don't overwrite it.**

Edit it with your editor of choice:

```bash
sudo nano /etc/nix/nix.conf     # or: sudo vi /etc/nix/nix.conf
```

Add this line at the end, then save (`Ctrl-O`, `Enter`, `Ctrl-X` in nano):

```
experimental-features = nix-command flakes
```

The finished file should look roughly like:

```
build-users-group = nixbld
experimental-features = nix-command flakes
```

Or do it in one non-interactive command:

```bash
echo "experimental-features = nix-command flakes" | sudo tee -a /etc/nix/nix.conf
```

**Now restart the Nix daemon.** This is the step people miss on macOS — the daemon
reads `/etc/nix/nix.conf` at startup, so your change does nothing until it reloads:

```bash
sudo launchctl kickstart -k system/org.nixos.nix-daemon
```

<details>
<summary>Linux equivalent</summary>

```bash
sudo systemctl restart nix-daemon
```
</details>

### Verify flakes are on

```bash
nix config show experimental-features
```

Expected output includes `flakes` and `nix-command`:

```
fetch-tree flakes nix-command
```

If instead you see:

```
error: experimental Nix feature 'nix-command' is disabled; add '--extra-experimental-features nix-command' to enable it
```

then the config didn't take effect — re-check the file path, and make sure you
restarted the daemon if you used Option B.

---

## Step 3 — Get this repo

```bash
git clone https://github.com/sandK-31/NixForRatpac.git
cd NixForRatpac
```

macOS ships `git` with the Xcode Command Line Tools; if it's missing, the first
`git` command triggers a prompt to install them. On Linux, install it with your
package manager (`apt install git`, `dnf install git`, …).

> **On WSL, clone into the Linux filesystem** — `~/NixForRatpac`, never
> `/mnt/c/Users/…`. Builds on the Windows drive are several times slower, and the
> DrvFs mount doesn't give Nix the permissions and symlinks it expects. To open
> the files from Windows apps, browse to `\\wsl.localhost\Ubuntu\home\<you>\`
> instead.

> **Or skip the clone entirely.** Nix can run a flake straight from GitHub:
>
> ```bash
> # everything: RAT-PAC + Geant4 + ROOT
> nix develop github:sandK-31/NixForRatpac
>
> # Geant4 + ROOT only, no RAT-PAC
> nix develop github:sandK-31/NixForRatpac#geant4
> ```
>
> The `#geant4` suffix picks *which* of the flake's two dev shells to enter.
> With no suffix you get the default shell, which includes RAT-PAC; `#geant4`
> selects the RAT-PAC-free one described in
> [Step 4](#without-rat-pac-geant4--root-only). The same suffix works on a
> clone, where it's written `nix develop .#geant4` — the `.` just means "the
> flake in this directory" instead of a GitHub URL.
>
> Running from GitHub is handy for a quick try, and the `$PWD/include` and
> `$PWD/lib` entries still point at whatever directory you ran it from. Clone
> if you want to edit `flake.nix` or pin your own RAT-PAC revision.

---

## Step 4 — Start the environment

From inside the clone:

```bash
nix develop
```

When it's ready you'll see:

```
Environment Ready: RAT-PAC 4.4.0 + Geant4 11.4.1 + ROOT 6.40.00
```

You're now in a Bash shell with `rat`, `root`, `geant4-config`, and the Python
environment on your `PATH`. Leave it with `exit` or `Ctrl-D`.

### Without RAT-PAC (Geant4 + ROOT only)

If you only want Geant4 and ROOT, use the `geant4` shell instead:

```bash
nix develop .#geant4
```

```
Environment Ready: Geant4 11.4.1 + ROOT 6.40.00 (no RAT-PAC)
```

This shell is identical to the default one minus RAT-PAC: same Geant4 (with Qt),
same ROOT, same datasets, same Python environment. RAT-PAC is not referenced by
it at all, so Nix never builds or downloads it — `rat` won't be on your `PATH`,
and `$RATROOT`, `$RATSHARE` and the RAT `$PYTHONPATH` entry are not set.

> **This skips the RAT-PAC build, not the Geant4 build.** The long first-run
> compile described below is mostly Geant4-with-Qt, which this shell still needs.
> Expect it to save you minutes, not hours. Once you've built either shell, the
> shared parts are cached and the other one starts fast.

The two shells are generated from a single function in `flake.nix`, so fixes to
the environment apply to both.

> ### ⏱️ The first run takes a long time — this is expected
>
> This flake builds Geant4 with Qt visualization enabled, which is a *different*
> build than the one in the public Nix binary cache. That means **Geant4 and
> RAT-PAC are compiled from source on your machine the first time** — budget
> anywhere from 30 minutes to a couple of hours depending on your CPU, plus a
> multi-GB download for ROOT and the Geant4 physics datasets.
>
> It is cached in `/nix/store` afterwards. Every later `nix develop` starts in
> under a second.
>
> Run it with `nix develop -L` if you want to watch the build logs instead of a
> spinner.

### Other ways to run it

```bash
# Run a single command in the environment without entering an interactive shell
nix develop --command rat -h

# Same, in the RAT-PAC-free shell
nix develop .#geant4 --command geant4-config --version

# Build just the RAT-PAC package; result appears at ./result
nix build

# Inspect what the flake provides (lists both dev shells)
nix flake show
```

---

## Step 5 — Check that it works

Inside `nix develop`:

```bash
which rat            # → /nix/store/…-ratpac-two-4.4.0/bin/rat
rat -h               # prints the RAT usage/options block
root-config --version    # → 6.40.00
geant4-config --version  # → 11.4.1
echo $RATROOT
```

`rat -h` may print a harmless cling warning before the usage text:

```
Error in cling::AutoLoadingVisitor::InsertIntoAutoLoadingState:
   Missing FileEntry for smart_ptr.hpp
```

This is a ROOT dictionary noise message, not a broken install. If the `usage: rat
[options] …` block follows it, you're fine.

**The full check** is one command, run from the clone (not inside `nix develop`):

```bash
tests/macos/run-tests.sh      # or tests/linux/…, or tests/windows/… inside WSL
```

It builds everything, then tests both shells, RAT-PAC (including its own
physics tests), CRY, ROOT, a standalone Geant4 build, and the Geant4, RAT-PAC
and ROOT windows, asking you what you saw at the end. See
[tests/README.md](tests/README.md).

> **One XFAIL is normal.** A clean run is every test PASS plus exactly one
> XFAIL, `rattest-geoprint`. That is the result on macOS, Linux and Windows
> (WSL). The test is broken upstream: its macro sets `DETECTOR geometry`, and
> RAT-PAC 4.4.0 reads `geo_file` instead. It fails the same way on every
> machine, so it says nothing about your install. Only a FAIL needs attention.

---

## What the shell sets up for you

| Variable | Value | In `.#geant4`? |
| --- | --- | --- |
| `RATROOT` | the RAT-PAC store path | — |
| `RATSHARE` | `$RATROOT/share/RAT` (macros, models, ratdb, python) | — |
| `PYTHONPATH` | `$RATSHARE/python` (the `rat`, `ratproc`, `rattest` modules) | — |
| `CPLUS_INCLUDE_PATH` | `$PWD/include`, RAT-PAC (with `include/stlplus`), ROOT, and Geant4 headers | yes, minus RAT-PAC |
| `ROOT_INCLUDE_PATH` | `$PWD/include`, RAT-PAC (with `include/stlplus`, which cling needs to read RAT's DS classes), and Geant4 headers | yes, minus RAT-PAC |
| `LD_LIBRARY_PATH` | `$PWD/lib`, `$RATROOT/lib`, Geant4 libs | yes, minus `$RATROOT/lib` |
| `DYLD_LIBRARY_PATH` | same as above — macOS ignores `LD_LIBRARY_PATH` | yes, minus `$RATROOT/lib` |
| `CRYLIB`, `CRYINCLUDE`, `CRYDATA` | CRY's `lib`, `include/cry` and data directories; RAT's `cry` generator reads `CRYDATA` at run time | yes |
| `QT_QPA_PLATFORM` | `cocoa` on macOS; on Linux `wayland` when there's a Wayland compositor (WSLg has one), `xcb` otherwise. A value you set before `nix develop` wins | yes |
| `__EGL_VENDOR_LIBRARY_FILENAMES`, `LIBGL_DRIVERS_PATH`, `GBM_BACKENDS_PATH` | Linux other than NixOS: nixpkgs' Mesa, whose `lib` (and WSL's `/usr/lib/wsl/lib`) also goes on `LD_LIBRARY_PATH`. Nix-built OpenGL programs otherwise find no driver | yes |
| `SHELL` | the Nix-provided Bash | yes |

The Geant4 dataset variables (`G4LEDATA`, `G4NEUTRONHPDATA`, …) are set
automatically by the dataset packages.

Note the `$PWD/include` and `$PWD/lib` entries: they're there so that if you run
`nix develop` from *your own experiment's* directory, your locally built headers
and libraries take precedence over the ones shipped with RAT-PAC.

---

## Updating and pinning

`flake.lock` pins exact revisions of nixpkgs, flake-utils, and the RAT-PAC source,
so everyone who checks out this repo gets a bit-for-bit identical environment.

```bash
# See exactly what's pinned right now
nix flake metadata

# Update nixpkgs / flake-utils to the latest
nix flake update
```

`ratpac-src` is pinned to the **`4.4.0` tag** in `flake.nix`, not to a branch, so
`nix flake update` will *not* move RAT-PAC. That's deliberate: the `postPatch`
section of `flake.nix` carries a workaround for an upstream bug, and a surprise
RAT-PAC bump is the most likely way to break this environment.

To move RAT-PAC deliberately, edit the `ratpac-src` URL in `flake.nix`, then:

```bash
nix flake update ratpac-src
nix build          # patch guards will flag any workaround that no longer applies
```

## What changed in this version

The previous version (tag `ratpac-3`) was stuck on RAT-PAC 3.x because tags
`4.0.0` and later declare `find_package(Geant4 11.4 REQUIRED)` while nixpkgs
`nixos-25.11` shipped Geant4 **11.3.2**. nixpkgs `nixos-26.05` ships
**11.4.1**, which clears that floor, so this version moves both at once.

Geant4 was the easy part. Three other things changed.

### Qt5 → Qt6

nixpkgs 26.05 switched geant4's `enableQt` from `qt5` to `qt6`. geant4
propagates `qt6.wrapQtAppsHook`, which aborts the build outright if Qt5 appears
anywhere in the same closure:

```
Error: detected mismatched Qt dependencies:
    /nix/store/…-qtbase-5.15.19-dev
    /nix/store/…-qtbase-6.11.2
```

So `pkgs.qt5.qtbase` in RAT-PAC's `buildInputs` became `pkgs.qt6.qtbase`. The
`shellHook` needed a second edit: `qt6.qtbase` has no `bin` output (only `out`
and `dev`), so `QT_PLUGIN_PATH` is built from the package itself, and the plugin
prefix moved to `lib/qt-6/plugins`.

**This is the part that broke on Linux.** The first test-suite run on
WSL (2026-10-14) found that Nix-built Qt had no OpenGL driver at all off NixOS:
Qt printed `EGL not available`, the OGLSQt viewer drew nothing, and the `rat -g`
window never appeared. `G4VIS_DEFAULT_DRIVER=TSG_QT_ZB`, a software renderer, had
been hiding this for standalone Geant4 apps; RAT registers no such driver. The
shell now points OpenGL at nixpkgs' Mesa on Linux other than NixOS, and with
that the viewer tests pass on Linux and WSL.

### RAT-PAC 4.3.0 → 4.4.0: libRATEvent is gone

The upgrade first pinned 4.3.0, which does not link on macOS. `libRATEvent`, a
slimmed-down sibling of `libRATPAC`, had four undefined symbols
(`RAT::PhysicsList`, `RAT::DetectorConstruction`, and `RAT::TransitTimeCalculator`'s
constructor and destructor) whose definitions live only in `libRATPAC`. Linux's
linker leaves undefined symbols in a shared library to load time; Apple's
refuses them. The upgrade got past it with a Darwin-only
`-Wl,-undefined,dynamic_lookup` in `cmakeFlags`.

Upstream hit the same failure on a Mac and fixed it in 4.4.0: the CMake
refactor ([#443](https://github.com/rat-pac/ratpac-two/pull/443)) and then
[#450](https://github.com/rat-pac/ratpac-two/pull/450) deleted `libRATEvent`
outright. The flag is gone with it, and `cmakeFlags` is now the same on both
platforms.

What that means if you build an experiment against this environment:

- **Linking `RATEvent` now fails**, because there is no `libRATEvent` to find.
  Drop it from `target_link_libraries`; `RATPAC` has always contained
  everything `RATEvent` did.
- **The rest of the CMake interface still works.** 4.4.0's `RatpacConfig.cmake`
  adds a `Ratpac::RATPAC` target but keeps the old `RATROOT`, `RATSHARE`,
  include-directory and link-directory settings, so `find_package(Ratpac)` plus
  a bare `RATPAC` link still resolves. Headers still install to
  `$RATROOT/include`.
- **Optical output can differ from 4.3.0.**
  [#447](https://github.com/rat-pac/ratpac-two/pull/447) changes how the
  Cherenkov, scintillation-waveform and WLS code read their property tables, to
  handle single-value vectors under Geant4 11.4, and lengthens reemission-time
  sampling ("from 3sigma to 30, consistent with scintillation timing
  sampling"), so timing results may not match a 4.3.0 run exactly.

### Two `postPatch` fixups deleted

Upstream fixed both between `905b40d` and `4.3.0`, and re-applying them would
rewrite correct code:

- **`TPython::Eval` → `Exec`** — `src/core/src/PythonProc.cc` now guards the old
  implementation behind `#if ROOT_VERSION_CODE < ROOT_VERSION(6, 34, 0)`. Note
  the old `fixup` guard would *not* have caught this: it greps for
  `TPython::Eval`, which still matches inside the dead branch.
- **`duration_cast(…).count()`** — already wrapped in `static_cast<long>` at all
  three call sites in `src/daq/src/WaveformAnalysisLucyDDM.cc`.

`copy-compile-commands` is still needed and still applies.

### CRY added

Unlike the three changes above, this one isn't forced by the move: the
previous version never had CRY either. RAT-PAC builds its `cry` vertex generator only if
`CRYLIB` is set when CMake configures, and nixpkgs has no CRY package, so
`flake.nix` now builds CRY 1.7 from the LLNL tarball and sets `CRYLIB`,
`CRYINCLUDE` and `CRYDATA` in both the RAT-PAC build and the dev shells, the
same three variables upstream's `ratpac-setup` exports.

`CRYDATA` matters at run time too: `VertexGen_CRY` reads it with `getenv()` when
the generator is created and segfaults if it's unset. Both shells set it, and
the `rat` binary also falls back to the packaged data directory when it's
missing, so a stripped environment can't crash it. Set `CRYDATA` yourself to
point at other tables.

To use it, swap the generator block in a macro for:

```
/generator/add combo cry:point:poisson
/generator/pos/set 0.0 0.0 1000.0    # where the shower plane sits, in mm
/generator/rate/set 1.0
```

Shower settings (particle types, altitude 0/2100/11300 m, latitude, date,
sub-box size) come from `$RATSHARE/ratdb/CRY.ratdb` and can be overridden with
`/rat/db/set CRY <field> <value>` before `/run/initialize`.

**Keep the sub-box inside your world volume.** The default `subboxLength` is
10, a 10 m × 10 m plane, so primaries start up to 5 m from `pos` in x and y.
In a world smaller than that, some start outside it, and RAT doesn't drop
them. A 20-event test in the Validation geometry (a 4.5 m-radius world) began
with `start point … is outside the world volume`, then spent 56 CPU-minutes
printing `GeomSolids1002` / `snxt = 9e+99` warnings, 2 GB of them, and had
not finished when it was killed. Set
`/rat/db/set CRY subboxLength 1` (allowed sizes: 1, 3, 10, 30, 100, 300 m) or
place `pos` so that the whole plane is inside the world.

### What has and hasn't been checked

Verified on aarch64-darwin with 4.4.0:

- the environment builds with no platform-specific `cmakeFlags`, and
  `nix develop` reports `RAT-PAC 4.4.0 + Geant4 11.4.1 + ROOT 6.40.00`;
- `rat -N 50 $RATSHARE/macros/examples/electron.mac` runs 50/50 triggered, and
  the ntuple reads back in ROOT with mean `mcpecount` 15.8, against 14.5 for
  the same 50 events on 4.3.0 (a sanity check at this statistics, not a physics
  comparison);
- a minimal downstream CMake project using `find_package(Ratpac)` and a bare
  `RATPAC` link compiles, links and runs;
- with CRY: configure reports `Compiling with CRY enabled`, `Config.hh` has
  `CRY_Enabled 1`, and `libRATPAC` links the packaged `libCRY`. Ten events of
  `/generator/add combo cry:point:poisson` in the Validation geometry (1 m
  sub-box, sea level) ran at 1.2 s/event and gave 7 μ± at 0.6–13 GeV and
  3 neutrons at 0.7–23 MeV, all downward-going;
- `nix develop .#geant4` enters, reports `Geant4 11.4.1 + ROOT 6.40.00 (no
  RAT-PAC)` and sets the CRY variables. Nothing has been compiled in it yet.

Since then, the full test suite (`tests/`), Qt6 viewer included, has passed on
macOS, Linux and Windows (WSL), apart from the expected `rattest-geoprint` XFAIL.

Not checked: Intel Macs (no test run, and the flake does not evaluate on
`x86_64-darwin`), any downstream experiment code compiled against ROOT 6.40, and
physics output compared with known-good results. The ROOT 6.36 → 6.40 jump
caused no trouble for RAT-PAC itself, but nothing else has been rebuilt against
it.

Each run also prints 19 `mat219` warnings, one per single-value
`SCINTWAVEFORM*`, `REEMITWAVEFORM*` or `SCINTMOD*` table in RAT's material
database (a single decay time is stored as a one-entry vector). The same 19
appear on 4.3.0 and 4.4.0. They are warnings, not errors; reading
one-entry tables like these correctly under Geant4 11.4 is what #447 fixed:

```
*** G4Exception : mat219
      issued by : G4MaterialPropertiesTable::AddProperty()
AddProperty warning. A material property vector must have more than one value.
```

One pre-existing startup warning is unchanged from the previous version and is not a
regression:

```
Error in cling::AutoLoadingVisitor::InsertIntoAutoLoadingState:
   Missing FileEntry for smart_ptr.hpp
```

If an update does break the build, revert the lock:

```bash
git checkout flake.lock
```

Keeping `flake.lock` committed is what makes this reproducible — don't delete it.

---

## Troubleshooting

**`error: experimental Nix feature 'nix-command' is disabled`**
Step 2 didn't take. Check `nix config show experimental-features`, and restart the
daemon if you edited `/etc/nix/nix.conf`.

**`command not found: nix` right after installing**
Open a new terminal, or `source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`.

**Nix disappeared after a macOS system update**
macOS updates can wipe `/etc/synthetic.conf`, which is what mounts the `/nix`
volume at boot. Re-add it:

```bash
echo "nix" | sudo tee -a /etc/synthetic.conf
```

then reboot. (The Determinate Systems installer handles this for you.)

**`postPatch: '<something>' no longer applies to <file> -- remove it`**
Upstream RAT-PAC fixed a bug that `flake.nix` was patching around, so the patch is
now obsolete. Delete that `fixup` line and its matching `sed`/`perl` command from
`postPatch`. (The guards exist so an obsolete patch fails here loudly rather than
silently matching nothing.)

**Build fails after `nix flake update`**
Usually an upstream RAT-PAC change conflicting with the `postPatch` fixups in
`flake.nix`. Revert `flake.lock` and investigate with `nix develop -L` to see the
real compiler error.

**`/nix/store` is getting huge**
```bash
nix store gc
```
Note this will delete the built Geant4/RAT-PAC unless something holds a GC root, so
the next `nix develop` will rebuild. To keep it permanently:
```bash
nix build --out-link ./result   # ./result is a GC root
```

**Geant4 Qt visualization doesn't open a window, or draws nothing (Linux)**
Look for `qt.qpa.wayland: EGL not available` or `libGL error` in the output: that
is OpenGL finding no driver. Off NixOS the shell supplies nixpkgs' Mesa, which
covers Intel and AMD GPUs, WSL (through `d3d12`), and software rendering. It
can't drive NVIDIA's proprietary driver. To try X11 instead of Wayland, set
the platform before entering the shell: `QT_QPA_PLATFORM=xcb nix develop`.

**PyROOT on Linux: `cannot allocate memory in static TLS block` … `failure loading library libRATDict.so`**
Geant4's default thread-local storage model, `initial-exec`, only works for
libraries loaded when a program starts. Python loads RAT-PAC, and with it
Geant4, later: when you `import rat`, read a RAT file, or run `rattest`. So the
flake builds Geant4 with `-DGEANT4_BUILD_TLS_MODEL=global-dynamic` on Linux,
as nixpkgs does for its Python-enabled Geant4, and RAT-PAC picks the model up
from Geant4's CMake config. If you still see this error, your build predates
that change: `git pull` and enter `nix develop` again, which rebuilds Geant4 and
RAT-PAC once. `geant4-config` should then contain
`geant4_tls_model="global-dynamic"`.

**`rat -g`: `parameter value (TSG) is not listed` … `Illegal parameter (0) </vis/open>`**
RAT registers its own short list of Geant4 drivers (the OpenGL Qt ones, no TSG),
so a bare `/vis/open`, which asks for Geant4's default TSG driver, fails and
stops the macro. Name the driver, as RAT's own `macros/visualizations/*.mac`
do: `/vis/open OGLSQt`. Once the viewer is up, RAT's output goes to its console
and to `rat.<host>.<pid>.log`, not the terminal.

**Windows: a window never draws and its title says `[WARN: COPY MODE]`**
This is a WSLg bug, not a RAT-PAC or Nix one. The digitizer — or any other GUI:
the Geant4 Qt viewer, a ROOT canvas, even `xeyes` — starts, gets a taskbar entry
with a blank preview, and never paints anything. WSLg failed to set up its
shared-memory channel to the host and fell back to copying pixels over RDP.
Tracked as [microsoft/WSL#40618](https://github.com/microsoft/WSL/issues/40618),
moved to [microsoft/wslg#1456](https://github.com/microsoft/wslg/issues/1456),
still open as of WSL 2.9.x (September 2026).

Confirm it's this and not your own code:

```bash
grep use_gfxredir /mnt/wslg/weston.log
# [12:01:31.023] RDP backend: use_gfxredir = 0    ← 0 is broken, 1 is healthy
```

*Fix it now* — restart WSLg's compositor in the WSL system distro. Takes a
second, and doesn't kill your shells or a running job:

```bash
wsl.exe -d "$WSL_DISTRO_NAME" --system -- sh -c 'kill $(pgrep -x weston)'
```

Relaunch the digitizer; the window appears and the warning is gone.

*Fix it for good* — the trigger is `/mnt/shared_memory` being absent when WSLg
starts, so mount it yourself at boot. Inside Ubuntu:

```bash
sudo mkdir -p /mnt/shared_memory
echo 'tmpfs /mnt/shared_memory tmpfs defaults 0 0' | sudo tee -a /etc/fstab
```

and make sure `/etc/wsl.conf` contains:

```
[automount]
mountFsTab=true
```

Then `wsl --shutdown` from PowerShell and start Ubuntu again.

The bug is racy, so it can return mid-session — classically after you close the
last GUI window, `msrdc.exe` exits, and you open a new one. When it does, the
`weston` one-liner above is the thing to keep handy. A plain `wsl --shutdown`
also clears it, at the cost of everything you had running.

---

## Layout

```
flake.nix    environment + RAT-PAC package definition
flake.lock   pinned input revisions — keep this committed
README.md    this file
tests/       one-command test suite per platform (tests/README.md)
```

---

## Test your install

Once everything is installed, run the test suite for your system. Run it from
the clone, not inside `nix develop`:

```bash
tests/macos/run-tests.sh      # macOS, from Terminal
tests/linux/run-tests.sh      # Linux, from a terminal on the desktop
tests/windows/run-tests.sh    # Windows: inside the Ubuntu (WSL 2) terminal
```

It takes a while the first time, because it builds the whole environment, and
it asks you about the windows it opens. A good result is every test PASS plus
one XFAIL, `rattest-geoprint`, which is expected (see
[Step 5](#step-5--check-that-it-works)). If anything FAILs, send the
`tests/results/<os>-<date>.tar.gz` it writes.

**[tests/README.md](tests/README.md)** has the rest: the options, what each
test checks, and how to read the results.
