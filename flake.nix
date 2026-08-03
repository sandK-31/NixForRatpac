# Initially written by Ethan W. Todd, https://github.com/ewtodd
# Adapted by Sander Katz, https://github.com/sandK-31
{
  description = "Unified Geant4 + ROOT + RAT-PAC (Latest Main) environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
    ratpac-src = {
      url = "github:rat-pac/ratpac-two/main";
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
          version = "unstable";
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
            qt5.qtbase
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

          # Upstream compatibility fixes. Each one is guarded by a grep so that if
          # ratpac-src moves and a fix stops applying, the build fails loudly here
          # instead of the sed silently matching nothing and failing later (or not
          # at all, leaving the fix quietly absent).
          postPatch = ''
            fixup() { # fixup <description> <file> <pattern>
              grep -q "$3" "$2" \
                || { echo "postPatch: '$1' no longer applies to $2 -- remove it"; exit 1; }
            }

            # The copy-compile-commands target writes into the source tree, which
            # is read-only in the Nix sandbox.
            fixup "copy-compile-commands" CMakeLists.txt 'copy-compile-commands'
            sed -i '/add_custom_target(/,/^)/{/copy-compile-commands/,/^)/d; /add_custom_target(/d}' CMakeLists.txt

            # ROOT 6.36 removed TPython::Eval; TPython::Exec is the replacement.
            fixup "TPython::Eval" src/core/src/PythonProc.cc 'TPython::Eval'
            sed -i 's/TPython::Eval/TPython::Exec/g' src/core/src/PythonProc.cc

            # `duration_cast<...>(...).count()` returns a rep that is ambiguous for
            # RAT's overloaded operator<<; pin it to long. Non-greedy match across
            # newlines, so it also catches the call split over two lines.
            fixup "chrono duration_cast" src/daq/src/WaveformAnalysisLucyDDM.cc 'duration_cast'
            find src -name "*.cc" -exec perl -0777 -pi \
              -e 's/(std::chrono::duration_cast<.*?>\(.*?\)\s*\.count\(\))/static_cast<long>($1)/gs' {} +
          '';

          meta = {
            description = "RAT-PAC 2 detector simulation and analysis framework";
            homepage = "https://github.com/rat-pac/ratpac-two";
            # Without this, `nix run` looks for bin/ratpac-two and fails.
            mainProgram = "rat";
          };
        };

      in
      {
        packages.default = ratpac;

        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.root
            geant4custom
            pkgs.cmake
            ratpac
            pkgs.bash
            pythonEnv
          ] ++ geant4Datasets;

          shellHook = ''
            export SHELL="${pkgs.bash}/bin/bash"
            export QT_PLUGIN_PATH="${pkgs.qt5.qtbase.bin}/${pkgs.qt5.qtbase.qtPluginPrefix}"

            ${if !isDarwin then ''
              export QT_QPA_PLATFORM=wayland
              export G4VIS_DEFAULT_DRIVER=TSG_QT_ZB
              export DISPLAY=:0
            '' else ''
              export QT_QPA_PLATFORM=cocoa
            ''}

            export RATROOT="${ratpac}"
            export RATSHARE="${ratpac}/share/RAT"
            
            G4_INC="$(geant4-config --prefix)/include/Geant4"
            ROOT_INC="$(root-config --incdir)"
            G4_LIB="$(geant4-config --prefix)/lib"

            export CPLUS_INCLUDE_PATH="$PWD/include:${ratpac}/include:$ROOT_INC:$G4_INC''${CPLUS_INCLUDE_PATH:+:$CPLUS_INCLUDE_PATH}"
            export ROOT_INCLUDE_PATH="$PWD/include:${ratpac}/include:$G4_INC''${ROOT_INCLUDE_PATH:+:$ROOT_INCLUDE_PATH}"

            # RAT's Python modules (rat, ratproc, rattest) live under $RATSHARE.
            export PYTHONPATH="$RATSHARE/python''${PYTHONPATH:+:$PYTHONPATH}"

            # macOS ignores LD_LIBRARY_PATH, so set both -- upstream's ratpac.sh
            # does the same. $PWD/lib comes first so a locally built experiment
            # library wins over the one shipped with RAT-PAC.
            RAT_LIB_PATH="$PWD/lib:${ratpac}/lib:$G4_LIB"
            export LD_LIBRARY_PATH="$RAT_LIB_PATH''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            export DYLD_LIBRARY_PATH="$RAT_LIB_PATH''${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"

            echo "Environment Ready: RAT-PAC (Latest Main) + Geant4 + ROOT"
          '';
        };
      }
    );
}