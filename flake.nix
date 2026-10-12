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

        fftw3-cmake = pkgs.writeTextDir "lib/cmake/FFTW3/FFTW3Config.cmake" ''
          if(NOT TARGET FFTW3::fftw3)
            add_library(FFTW3::fftw3 SHARED IMPORTED)
            set_target_properties(FFTW3::fftw3 PROPERTIES
              IMPORTED_LOCATION "${pkgs.fftw}/lib/libfftw3${if isDarwin then ".dylib" else ".so"}"
              INTERFACE_INCLUDE_DIRECTORIES "${pkgs.fftw.dev}/include"
            )
          endif()
          set(FFTW3_FOUND TRUE)
        '';

        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          numpy
          root
          plotly
          particle
        ]);

        ratpac = pkgs.stdenv.mkDerivation {
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
            "-DFFTW3_DIR=${fftw3-cmake}/lib/cmake/FFTW3"
          ];

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
        };

        # Both dev shells are built from this one function so they cannot drift
        # apart. withRatpac = false drops RAT-PAC from buildInputs entirely, so
        # `nix develop .#geant4` never builds or downloads it.
        mkRatpacShell = { withRatpac }:
          let
            inherit (pkgs.lib) optionalString;
            # Trailing colon is part of the string, so it disappears along with
            # the path when RAT-PAC is not included.
            ratpacInc = optionalString withRatpac "${ratpac}/include:";
            ratpacLib = optionalString withRatpac "${ratpac}/lib:";
          in
          pkgs.mkShell {
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
                export QT_QPA_PLATFORM=wayland
                export G4VIS_DEFAULT_DRIVER=TSG_QT_ZB
                export DISPLAY=:0
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
          };

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
