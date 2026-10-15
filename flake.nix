# Initially written by Ethan W. Todd, https://github.com/ewtodd
# Adapted by Sander Katz, https://github.com/sandK-31
{
  description = "Unified Geant4 + ROOT + RAT-PAC development environment";

  inputs = {
    # 26.05 rather than 25.11: it ships Geant4 11.4.1, which is what the
    # RAT-PAC 4.x line requires (find_package(Geant4 11.4 REQUIRED)).
    # It also carries ROOT 6.40.00, up from 6.36.04 on 25.11; that jump turned
    # out to cost nothing. What the channel bump did cost is the Qt6 switch,
    # commented where it applies.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
    # Tag 4.4.0 (commit 346c4cf, 2026-10-11), which at the time of writing is
    # also the head of main. A tag is immutable enough that `nix flake update`
    # cannot move RAT-PAC underneath the postPatch workaround below.
    ratpac-src = {
      url = "github:rat-pac/ratpac-two/4.4.0";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, ratpac-src }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        isDarwin = pkgs.stdenv.isDarwin;

        geant4custom = pkgs.geant4.override { enableQt = true; };
        geant4Datasets = with pkgs.geant4.data; [
          G4ABLA G4INCL G4PhotonEvaporation G4RealSurface G4EMLOW 
          G4NDL G4PII G4SAIDDATA G4ENSDFSTATE G4PARTICLEXS 
          G4TENDL G4RadioactiveDecay
        ];

        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          numpy
          root
          plotly
          particle
        ]);

        # CRY 1.7, LLNL's cosmic-ray shower generator, behind RAT-PAC's `cry`
        # vertex generator. nixpkgs does not package it. Laid out the way
        # upstream's ratpac-setup installs it (shared libCRY, headers under
        # include/cry), but src/*.cc is compiled directly: the shipped
        # Makefile has CRLF line endings and only builds a static archive,
        # which ratpac-setup patches by line number.
        cry = pkgs.stdenv.mkDerivation {
          pname = "cry";
          version = "1.7";
          src = pkgs.fetchurl {
            url = "https://nuclear.llnl.gov/simulation/cry_v1.7.tar.gz";
            hash = "sha256-3O4kKPgcuhE/guDHxC9Nhb/0uFMOWrXILAWb7T5XDCA=";
          };

          buildPhase = ''
            runHook preBuild
            $CXX -O2 -fPIC -shared -Isrc src/*.cc -o libCRY${pkgs.stdenv.hostPlatform.extensions.sharedLibrary} \
              ${pkgs.lib.optionalString isDarwin "-Wl,-install_name,$out/lib/libCRY.dylib"}
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            install -Dm755 -t $out/lib libCRY${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}
            install -Dm644 -t $out/include/cry src/*.h
            # Per-altitude tables (0, 2100, 11300 m), read at run time from $CRYDATA.
            install -Dm644 -t $out/share/cry/data data/*
            runHook postInstall
          '';

          meta = {
            description = "Cosmic-ray shower generator (LLNL)";
            homepage = "https://nuclear.llnl.gov/simulation/";
          };
        };

        # The variables ratpac-setup's env.sh exports. RAT-PAC's CMake turns
        # CRY on only if CRYLIB is set when it configures, and VertexGen_CRY
        # reads CRYDATA with getenv() at run time.
        cryEnv = {
          CRYLIB = "${cry}/lib";
          CRYINCLUDE = "${cry}/include/cry";
          CRYDATA = "${cry}/share/cry/data";
        };

        ratpac = pkgs.stdenv.mkDerivation (cryEnv // {
          pname = "ratpac-two";
          version = "4.4.0";
          src = ratpac-src;

          nativeBuildInputs = with pkgs; [
            cmake
            pkg-config
            perl
          ];

          buildInputs = [
            geant4custom
            pkgs.root
            pythonEnv
            cry
          ] ++ (with pkgs; [
            fftw
            fftwFloat
            xercesc
            clhep
            curl
            openssl
            zlib
            libx11
            libxpm
            libxft
            libxext
            # Qt6, not Qt5: nixpkgs 26.05 switched geant4's enableQt to qt6, and
            # geant4 propagates qt6.wrapQtAppsHook, which aborts the build if it
            # finds Qt5 anywhere in the same closure.
            qt6.qtbase
          ]) ++ pkgs.lib.optionals (!isDarwin) (with pkgs; [
            # null on darwin, so these only ever contribute on Linux
            libGL
            libGLU
            libxkbcommon
          ]);

          propagatedBuildInputs = geant4Datasets;

          cmakeFlags = [
            "-DCMAKE_INSTALL_PREFIX=${placeholder "out"}"
            "-DCMAKE_BUILD_TYPE=Release"
            "-DROOT_DIR=${pkgs.root}/cmake"
          ];

          # The binaries are already wrapped by wrapQtAppsHook (propagated by
          # geant4). Without CRYDATA, VertexGen_CRY segfaults in its
          # constructor, so give rat a default for when it runs outside the
          # dev shell's environment; a CRYDATA already set still wins.
          qtWrapperArgs = [ "--set-default" "CRYDATA" cryEnv.CRYDATA ];

          # Upstream compatibility fix, guarded by a grep so that if ratpac-src
          # moves and it stops applying, the build fails loudly here instead of
          # the sed silently matching nothing.
          #
          # Two patches carried before the 26.05 bump are gone: as of 4.3.0
          # upstream guards the TPython::Eval path behind
          # `#if ROOT_VERSION_CODE < ROOT_VERSION(6, 34, 0)`, and it already
          # wraps every duration_cast(...).count() in static_cast<long>.
          # Re-applying either here would rewrite correct code.
          postPatch = ''
            fixup() { # fixup <description> <file> <pattern>
              grep -q "$3" "$2" \
                || { echo "postPatch: '$1' no longer applies to $2 -- remove it"; exit 1; }
            }

            # The copy-compile-commands target writes into the source tree, which
            # is read-only in the Nix sandbox.
            fixup "copy-compile-commands" CMakeLists.txt 'copy-compile-commands'
            sed -i '/add_custom_target(/,/^)/{/copy-compile-commands/,/^)/d; /add_custom_target(/d}' CMakeLists.txt
          '';

          meta = {
            description = "RAT-PAC 2 detector simulation and analysis framework";
            homepage = "https://github.com/rat-pac/ratpac-two";
            # Without this, `nix run` looks for bin/ratpac-two and fails.
            mainProgram = "rat";
          };
        });

        # Both dev shells are built from this one function so they cannot drift
        # apart. withRatpac = false drops RAT-PAC from buildInputs entirely, so
        # `nix develop .#geant4` never builds or downloads it.
        mkRatpacShell = { withRatpac }:
          let
            inherit (pkgs.lib) optionalString;
            # Trailing colon is part of the string, so it disappears along with
            # the path when RAT-PAC is not included.
            #
            # include/stlplus is needed because RAT/Log.hh includes
            # "dprintf.hpp" from there. libRATDict's payload pulls in Log.hh,
            # and the include paths baked into the dictionary point at the
            # long-gone build sandbox, so without this cling cannot parse
            # RAT::DS::Root and DS-reading ROOT macros and PyROOT fail.
            ratpacInc = optionalString withRatpac
              "${ratpac}/include:${ratpac}/include/stlplus:";
            ratpacLib = optionalString withRatpac "${ratpac}/lib:";
          in
          # cryEnv goes into both shells: the CRY library is not RAT-PAC
          # specific, and a RAT-PAC built from source inside the shell picks
          # it up the same way the package above does.
          pkgs.mkShell (cryEnv // {
            # Order matters: it sets PATH precedence. Keep RAT-PAC in the same
            # slot it occupied before this shell was made optional.
            buildInputs = [
              pkgs.root
              geant4custom
              pkgs.cmake
            ] ++ pkgs.lib.optional withRatpac ratpac
              ++ [
              pkgs.bash
              pythonEnv
            ] ++ geant4Datasets;

            shellHook = ''
              export SHELL="${pkgs.bash}/bin/bash"
              # qt6.qtbase has no `bin` output (just out/dev), unlike qt5.qtbase.
              export QT_PLUGIN_PATH="${pkgs.qt6.qtbase}/${pkgs.qt6.qtbase.qtPluginPrefix}"

              ${if !isDarwin then ''
                # Defaults only, so `QT_QPA_PLATFORM=xcb nix develop` and the
                # like still win. Wayland where there is a compositor (WSLg
                # has one), X11 otherwise.
                if [ -z "''${QT_QPA_PLATFORM:-}" ]; then
                  if [ -n "''${WAYLAND_DISPLAY:-}" ]; then
                    export QT_QPA_PLATFORM=wayland
                  else
                    export QT_QPA_PLATFORM=xcb
                  fi
                fi
                export G4VIS_DEFAULT_DRIVER="''${G4VIS_DEFAULT_DRIVER:-TSG_QT_ZB}"
                export DISPLAY="''${DISPLAY:-:0}"

                # Nix-built OpenGL programs look for the GPU driver under
                # /run/opengl-driver, which only NixOS has. Anywhere else Qt
                # reports "EGL not available", OGLSQt draws nothing, and the
                # rat -g window never appears (RAT has no software-only
                # driver). Point libglvnd at nixpkgs' Mesa instead: d3d12 on
                # WSL (through /usr/lib/wsl/lib), iris/radeonsi on Intel/AMD,
                # llvmpipe in software otherwise.
                if [ ! -d /run/opengl-driver/lib ]; then
                  export __EGL_VENDOR_LIBRARY_FILENAMES="${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json"
                  export LIBGL_DRIVERS_PATH="${pkgs.mesa}/lib/dri"
                  export GBM_BACKENDS_PATH="${pkgs.mesa}/lib/gbm"
                  NFR_GL_LIB="${pkgs.mesa}/lib"
                  if [ -d /usr/lib/wsl/lib ]; then
                    NFR_GL_LIB="$NFR_GL_LIB:/usr/lib/wsl/lib"
                  fi
                  export LD_LIBRARY_PATH="$NFR_GL_LIB''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
                  unset NFR_GL_LIB
                fi

                # numpy, through OpenBLAS, loads gfortran's copy of
                # libstdc++; cling then dlopens gcc's copy by path for
                # libRATDict, and the second copy finds glibc's spare static
                # TLS used up ("cannot allocate memory in static TLS block"),
                # so PyROOT can't read RAT files and rattest fails. Reserve
                # more of it.
                export GLIBC_TUNABLES="''${GLIBC_TUNABLES:+$GLIBC_TUNABLES:}glibc.rtld.optional_static_tls=16384"
              '' else ''
                export QT_QPA_PLATFORM=cocoa
              ''}

              ${optionalString withRatpac ''
                export RATROOT="${ratpac}"
                export RATSHARE="${ratpac}/share/RAT"
              ''}

              G4_INC="$(geant4-config --prefix)/include/Geant4"
              ROOT_INC="$(root-config --incdir)"
              G4_LIB="$(geant4-config --prefix)/lib"

              export CPLUS_INCLUDE_PATH="$PWD/include:${ratpacInc}$ROOT_INC:$G4_INC''${CPLUS_INCLUDE_PATH:+:$CPLUS_INCLUDE_PATH}"
              export ROOT_INCLUDE_PATH="$PWD/include:${ratpacInc}$G4_INC''${ROOT_INCLUDE_PATH:+:$ROOT_INCLUDE_PATH}"

              ${optionalString withRatpac ''
                # RAT's Python modules (rat, ratproc, rattest) live under $RATSHARE.
                export PYTHONPATH="$RATSHARE/python''${PYTHONPATH:+:$PYTHONPATH}"
              ''}

              # macOS ignores LD_LIBRARY_PATH, so set both -- upstream's ratpac.sh
              # does the same. $PWD/lib comes first so a locally built experiment
              # library wins over anything else on the path.
              RAT_LIB_PATH="$PWD/lib:${ratpacLib}$G4_LIB"
              export LD_LIBRARY_PATH="$RAT_LIB_PATH''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
              export DYLD_LIBRARY_PATH="$RAT_LIB_PATH''${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"

              echo "Environment Ready: ${
                if withRatpac then "RAT-PAC ${ratpac.version} + " else ""
              }Geant4 $(geant4-config --version) + ROOT $(root-config --version)${
                if withRatpac then "" else " (no RAT-PAC)"
              }"
            '';
          });

      in
      {
        packages.default = ratpac;

        devShells.default = mkRatpacShell { withRatpac = true; };

        # `nix develop .#geant4` -- Geant4 + ROOT + Python only, for people who
        # do not want RAT-PAC built on their machine.
        devShells.geant4 = mkRatpacShell { withRatpac = false; };
      }
    );
}
