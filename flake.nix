{
  description = "f6-appkit — fetch/build/deploy Flipper catalog apps for the f6 backport";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAll = nixpkgs.lib.genAttrs systems;

      # fbt's pinned toolchain (scripts/toolchain/fbtenv.sh: FBT_TOOLCHAIN_VERSION).
      # Bump alongside the firmware fork and refresh the hashes below.
      toolchainVersion = "39";

      # nix system -> fbtenv's "$(uname -m)-$(uname -s)" dir name
      comboFor = {
        "aarch64-darwin" = "arm64-darwin";
        "x86_64-darwin"  = "x86_64-darwin";
        "aarch64-linux"  = "aarch64-linux";
        "x86_64-linux"   = "x86_64-linux";
      };

      toolchainHashes = {
        "arm64-darwin"  = "sha256-1sb8NWB6+ao1fVSdKfIweZyRuXO5OM53blXhqLmdrqA=";
        "x86_64-darwin" = "sha256-lTYMTaP7cY/o1xFvEvNKFVWNrGBP0GQZ8V8MsGGtV4M=";
        "aarch64-linux" = "sha256-0GxLACM7OcO0XB4U/tZj1F7WMUoJ8gwq9u0Xni3OOEk=";
        "x86_64-linux"  = "sha256-wETFkjP2b278+FSv/i1eCdutBNaHCdUTvHYLHZiJWFM=";
      };

      mkToolchain = system:
        let
          pkgs = import nixpkgs { inherit system; };
          lib = pkgs.lib;
          combo = comboFor.${system};
          unpacked = "gcc-arm-none-eabi-12.3-${combo}-flipper";
        in pkgs.stdenvNoCC.mkDerivation {
          pname = "flipper-toolchain";
          version = toolchainVersion;

          src = pkgs.fetchurl {
            url = "https://update.flipperzero.one/builds/toolchain/${unpacked}-${toolchainVersion}.tar.gz";
            hash = toolchainHashes.${combo};
          };

          # The tarball is a prebuilt gcc-arm-none-eabi + bundled python/scons/openocd.
          # On Linux its ELFs need their interpreter/rpath fixed for the nix store.
          nativeBuildInputs = lib.optionals pkgs.stdenv.isLinux [ pkgs.autoPatchelfHook ];
          buildInputs = lib.optionals pkgs.stdenv.isLinux (with pkgs; [
            stdenv.cc.cc.lib zlib ncurses5 expat xz libxml2 openssl
          ]);
          # The toolchain ships optional bits we don't all use; don't fail on those.
          autoPatchelfIgnoreMissingDeps = true;

          dontConfigure = true;
          dontBuild = true;

          # nix unpackPhase already cd's into the tarball's single root dir.
          installPhase = ''
            runHook preInstall
            mkdir -p "$out/toolchain/${combo}"
            cp -r . "$out/toolchain/${combo}"
            runHook postInstall
          '';
        };

      toolchains = forAll mkToolchain;
    in {
      packages = forAll (system: {
        flipper-toolchain = toolchains.${system};
        default = toolchains.${system};
      });

      devShells = forAll (system:
        let
          pkgs = import nixpkgs { inherit system; };
          # storage.py (from the firmware tree) needs these to talk over USB CDC
          py = pkgs.python3.withPackages (ps: [ ps.pyserial ps.colorlog ]);
          toolchain = toolchains.${system};
        in {
          default = pkgs.mkShell {
            packages = [ pkgs.just py pkgs.git pkgs.dfu-util pkgs.unzip pkgs.rsync ];
            # Point fbt at the nix-packaged toolchain so it never hits the network.
            # fbtenv finds toolchain/<arch>-<sys>/, checks VERSION, prepends its bin.
            FBT_TOOLCHAIN_PATH = "${toolchain}";
            shellHook = ''
              export FBT_NO_SYNC=1
              echo "f6-appkit — toolchain v${toolchainVersion} pinned at $FBT_TOOLCHAIN_PATH"
              echo "run 'just' for recipes"
            '';
          };
        });
    };
}
