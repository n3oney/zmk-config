{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    zmk-nix = {
      url = "github:lilyinstarlight/zmk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = {
    self,
    nixpkgs,
    zmk-nix,
  }: let
    forAllSystems = nixpkgs.lib.genAttrs (nixpkgs.lib.attrNames zmk-nix.packages);
  in {
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      zmk = zmk-nix.legacyPackages.${system};

      commonArgs = {
        src = nixpkgs.lib.sourceFilesBySuffices self [
          ".board"
          ".cmake"
          ".conf"
          ".defconfig"
          "_defconfig"
          ".dts"
          ".dtsi"
          ".json"
          ".keymap"
          ".overlay"
          ".shield"
          ".yml"
          ".yaml"
        ];
        board = "nice_nano_v2";
        zephyrDepsHash = "sha256-Pn8VuXyZ7I7rccaaQmnJifuzrcKW85fAZdSZ6cD7hb4=";
        meta = {
          description = "ZMK firmware";
          license = nixpkgs.lib.licenses.mit;
          platforms = nixpkgs.lib.platforms.all;
        };
      };

      left = (zmk.buildKeyboard (commonArgs
        // {
          name = "firmware";
          shield = "corne_left";
          # snippets = ["zmk-usb-logging"];

          extraCmakeFlags = [
            "-DEXTRA_DTC_OVERLAY_FILE=/build/source/config/corne_left_custom.overlay"
          ];
        })).overrideAttrs (old: {
        preBuild =
          (old.preBuild or "")
          + ''
            patch -p1 -d /build/source/zmk-input-gestures < ${./patches/inertial_cursor.patch}
            patch -p1 -d /build/source/cirque-input-module < ${./patches/cirque-input-module.patch}
          '';
      });

      right = (zmk.buildKeyboard (commonArgs
        // {
          name = "firmware-right";
          shield = "corne_right nice_view_adapter nice_view_battery_peripheral";
          westDeps = left.westDeps;

          extraCmakeFlags = [
            "-DEXTRA_DTC_OVERLAY_FILE=/build/source/config/corne_right_custom.overlay"
          ];
        })).overrideAttrs (
        old: {
          preBuild =
            (old.preBuild or "")
            + ''
              patch -p1 -d /build/source/nice-view-battery-peripheral < ${./patches/screen_battery.patch}
            '';
        }
      );

      settings_reset = zmk.buildKeyboard {
        name = "settings_reset";
        board = "nice_nano_v2";
        shield = "settings_reset";
        src = commonArgs.src;
        zephyrDepsHash = commonArgs.zephyrDepsHash;
        westDeps = left.westDeps;
      };
    in rec {
      inherit settings_reset;
      default = firmware;

      firmware =
        pkgs.runCommand "firmware" {
          parts = ["left" "right"];
        } ''
          mkdir $out
          ln -s ${left}/zmk.uf2 $out/zmk_left.uf2
          ln -s ${right}/zmk.uf2 $out/zmk_right.uf2
        '';

      flash = zmk-nix.packages.${system}.flash.override {inherit firmware;};
      update = zmk-nix.packages.${system}.update;
    });
    devShells = forAllSystems (system: {
      default = zmk-nix.devShells.${system}.default;
    });
  };
}
