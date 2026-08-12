{
  description = "NixOS configurations for Raspberry Pi devices";

  inputs = {
    # Top-level nixpkgs only used for sops-nix follows + tooling. The actual
    # NixOS systems are built against nvmd's pinned nixpkgs (currently 25.11).
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Unified upstream for ALL Pi hosts (see memory/project_upstream_strategy.md).
    # nvmd is the active successor to the archived raspberry-pi-nix; it covers
    # Pi 02 / 3 / 4 / 5 + CM4 / CM5 with vendor kernel + firmware, and the
    # uConsole flake (when we add it) is a thin layer over this.
    # Pin to a tagged release, NEVER track main/develop.
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/v1.20260317.0";
  };

  nixConfig = {
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };
  # NOTE: this nixConfig only blesses substituters at the EVALUATOR (your Mac's
  # nix CLI). For aarch64-linux builds dispatched to the linux-builder VM, the
  # VM's nix-daemon needs the substituter in ITS nix.conf — set via
  # nix-darwin's `nix.linux-builder.config.nix.settings.extra-substituters`.
  # Without that, the VM rebuilds Pi kernels from source even when nvmd has
  # them cached (~4-hour kernel rebuild).

  outputs = { self, nixpkgs, sops-nix, nixos-raspberrypi, ... }:
    let
      # All hosts use nvmd's lib so its overlays (raspberrypi-utils, vendor
      # kernel, etc.) get applied to pkgs. nvmd defaults nixpkgs to its own
      # pinned input (25.11) — we let it stay there for Cachix kernel hits.
      mkHost = { hostName, modules }:
        nixos-raspberrypi.lib.nixosSystem {
          specialArgs = { inherit nixos-raspberrypi; };
          modules = [
            sops-nix.nixosModules.sops
            ./modules/common.nix
            ./modules/users.nix
            ./modules/ssh.nix
            { networking.hostName = hostName; }
          ] ++ modules;
        };
    in {
      nixosConfigurations = {
        streamer-basement-workbench = mkHost {
          hostName = "streamer-basement-workbench";
          modules = [ ./hosts/streamer-basement-workbench ];
        };
        ups-compute-rack = mkHost {
          hostName = "ups-compute-rack";
          modules = [ ./hosts/ups-compute-rack ];
        };
        ups-office = mkHost {
          hostName = "ups-office";
          modules = [ ./hosts/ups-office ];
        };
      };
    };
}
