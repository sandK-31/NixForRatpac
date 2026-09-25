# NixForRatpac

A single [Nix flake](https://nixos.wiki/wiki/Flakes) that gives you a reproducible
**RAT-PAC 2 + Geant4 + ROOT** development environment with one command:

```bash
nix develop
```

No `apt`/`brew` packages to install, no manual CMake builds, no `LD_LIBRARY_PATH`
archaeology. Works on macOS (Apple Silicon and Intel) and Linux, and on Windows
through WSL 2 — see [Step 1](#windows-wsl-2).

> Originally written by [Ethan W. Todd](https://github.com/ewtodd), adapted by
> [Sander Katz](https://github.com/sandK-31).

**What you get inside the shell**

| Component | Version (as pinned) |
| --- | --- |
| RAT-PAC 2 | `rat-pac/ratpac-two` @ `905b40d` (2026-03-23) |
| Geant4 | 11.3.2, built with Qt visualization enabled |
| ROOT | 6.36.04 |
| Geant4 datasets | G4NDL, G4EMLOW, G4PhotonEvaporation, G4RadioactiveDecay, … |
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

Nix on macOS is always a *multi-user* (daemon) install. Run the official installer:

```bash
sh <(curl -L https://nixos.org/nix/install)
```

It will ask for your password (it creates a separate `/nix` APFS volume and a
`nixbld` user group). Answer `y` when it asks to proceed.

### Linux

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
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
sh <(curl -L https://nixos.org/nix/install) --daemon
```

> If you can't enable systemd (locked-down machine, ancient WSL), the single-user
> install works too: `sh <(curl -L https://nixos.org/nix/install) --no-daemon`.
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
Environment Ready: RAT-PAC 905b40d + Geant4 11.3.2 + ROOT 6.36.04
```

You're now in a Bash shell with `rat`, `root`, `geant4-config`, and the Python
environment on your `PATH`. Leave it with `exit` or `Ctrl-D`.

### Without RAT-PAC (Geant4 + ROOT only)

If you only want Geant4 and ROOT, use the `geant4` shell instead:

```bash
nix develop .#geant4
```

```
Environment Ready: Geant4 11.3.2 + ROOT 6.36.04 (no RAT-PAC)
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
which rat            # → /nix/store/…-ratpac-two-unstable/bin/rat
rat -h               # prints the RAT usage/options block
root-config --version    # → 6.36.04
geant4-config --version  # → 11.3.2
echo $RATROOT
```

`rat -h` may print a harmless cling warning before the usage text:

```
Error in cling::AutoLoadingVisitor::InsertIntoAutoLoadingState:
   Missing FileEntry for smart_ptr.hpp
```

This is a ROOT dictionary noise message, not a broken install. If the `usage: rat
[options] …` block follows it, you're fine.

---

## What the shell sets up for you

| Variable | Value | In `.#geant4`? |
| --- | --- | --- |
| `RATROOT` | the RAT-PAC store path | — |
| `RATSHARE` | `$RATROOT/share/RAT` (macros, models, ratdb, python) | — |
| `PYTHONPATH` | `$RATSHARE/python` (the `rat`, `ratproc`, `rattest` modules) | — |
| `CPLUS_INCLUDE_PATH` | `$PWD/include`, RAT-PAC, ROOT, and Geant4 headers | yes, minus RAT-PAC |
| `ROOT_INCLUDE_PATH` | `$PWD/include`, RAT-PAC, and Geant4 headers | yes, minus RAT-PAC |
| `LD_LIBRARY_PATH` | `$PWD/lib`, `$RATROOT/lib`, Geant4 libs | yes, minus `$RATROOT/lib` |
| `DYLD_LIBRARY_PATH` | same as above — macOS ignores `LD_LIBRARY_PATH` | yes, minus `$RATROOT/lib` |
| `QT_QPA_PLATFORM` | `cocoa` on macOS, `wayland` on Linux | yes |
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

`ratpac-src` is pinned to an **explicit commit** (`905b40d`) in `flake.nix`, not to
a branch, so `nix flake update` will *not* move RAT-PAC. That's deliberate: the
`postPatch` section of `flake.nix` carries workarounds for upstream bugs, and a
surprise RAT-PAC bump is the most likely way to break this environment.

To move RAT-PAC deliberately, edit the `ratpac-src` URL in `flake.nix`, then:

```bash
nix flake update ratpac-src
nix build          # patch guards will flag any workaround that no longer applies
```

> ### ⚠️ RAT-PAC 4.x needs a newer Geant4 than this flake provides
>
> Tags `4.0.0` and `4.1.0` declare `find_package(Geant4 11.4 REQUIRED)`, but
> nixpkgs `nixos-25.11` ships Geant4 **11.3.2**, so they fail at CMake configure:
>
> ```
> Could not find a configuration file for package "Geant4" that is
> compatible with requested version "11.4".
> ```
>
> Tag `3.4.0` and earlier have no Geant4 version floor and do build here.
> Going to 4.x means moving `nixpkgs` to a channel with Geant4 11.4
> (`nixos-unstable` has 11.4.2), which rebuilds ROOT and Geant4 from source and
> will likely require reworking the `postPatch` fixups.

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

**Geant4 Qt visualization doesn't open a window (Linux)**
The flake sets `QT_QPA_PLATFORM=wayland` and `DISPLAY=:0`. On an X11-only session
try `QT_QPA_PLATFORM=xcb nix develop`.

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
```
