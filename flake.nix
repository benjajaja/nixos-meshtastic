{
  description = "Meshtastic (native) for NixOS";

  inputs = {
    # Pinned to this commit for scons 4.5.2, which matches the version
    # in the bundled pio.tar (metadata shows 4.40502.0 = scons 4.5.2).
    # This allows replacing the scons executable without version spoofing.
    nixpkgs.url = "github:nixos/nixpkgs/b60793b86201040d9dee019a05089a9150d08b5b";
  };

  outputs = { self, nixpkgs }@inputs: let
    allSystems = nixpkgs.lib.systems.flakeExposed;
    forSystems = systems: f: nixpkgs.lib.genAttrs systems (system: f system);
  in {

    devShells = forSystems allSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        name = "nixos-meshtastic";
        nativeBuildInputs = with pkgs; [
          nil # lsp language server for nix
          nixpkgs-fmt
          nix-output-monitor
        ];
      };
    });

    nixosModules = {
      default = { config, lib, pkgs, ... }@args: import ./modules/meshtastic.nix {
        inherit config lib pkgs self;
      };

      # Tries to automagically configure SPI and I2C on Raspberry Pi
      # with `config.txt`
      # requires nvmd/nixos-raspberrypi
      raspberry-pi = import ./modules/raspberry-pi.nix;
    };

    packages = forSystems allSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {

      meshtasticd = pkgs.callPackage ./pkgs/meshtasticd.nix {
        inherit (self.packages.${system}) libyaml-cpp ulfius;
      };

      libyaml-cpp = pkgs.callPackage ./pkgs/libyaml-cpp.nix {};
      ulfius = pkgs.callPackage ./pkgs/ulfius.nix {};

    });

  };

}