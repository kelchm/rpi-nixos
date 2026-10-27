{
  description = "NixOS configurations for Raspberry Pi devices";

  inputs = {
    # Host userspace follows this stable channel independently of Pi releases.
    # nvmd keeps its own nixpkgs input for cached kernel/firmware packages;
    # do not make that input follow this one.
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
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/v1.20260801.0";

    # Sources for pkgs/, pinned to release tags. Dependabot moves a tag and
    # relocks, and each package takes its version from its tag.
    shairport-sync = { url = "github:mikebrady/shairport-sync/5.6.2"; flake = false; };
    nqptp = { url = "github:mikebrady/nqptp/1.2.9"; flake = false; };
    piaware = { url = "github:flightaware/piaware/v11.1"; flake = false; };
    tcllauncher = { url = "github:flightaware/tcllauncher/v1.10"; flake = false; };
    mlat-client = { url = "github:mutability/mlat-client/v0.2.13"; flake = false; };
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

  outputs = { self, nixpkgs, sops-nix, nixos-raspberrypi, ... }@inputs:
    let
      # The pkgs/ sources as { src, version }, with the version read from the
      # locked tag so the two can't drift apart.
      lock = builtins.fromJSON (builtins.readFile ./flake.lock);
      sources = nixpkgs.lib.genAttrs
        [ "shairport-sync" "nqptp" "piaware" "tcllauncher" "mlat-client" ]
        (name: {
          src = inputs.${name};
          version = nixpkgs.lib.removePrefix "v"
            lock.nodes.${lock.nodes.${lock.root}.inputs.${name}}.original.ref;
        });

      # Passing nixpkgs here changes host userspace, without changing the
      # nixpkgs that builds nvmd's kernel/firmware package outputs.
      mkHost = { hostName, modules }:
        nixos-raspberrypi.lib.nixosSystem {
          inherit nixpkgs;
          specialArgs = { inherit nixos-raspberrypi sources; };
          modules = [
            sops-nix.nixosModules.sops
            ./modules/common.nix
            ./modules/hardware/platform.nix
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
        adsb-office = mkHost {
          hostName = "adsb-office";
          modules = [ ./hosts/adsb-office ];
        };
      };

      checks.aarch64-linux.wireless-firmware =
        import ./.github/ci/wireless-firmware.nix {
          host = self.nixosConfigurations.streamer-basement-workbench;
        };
    };
}
