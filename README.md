# rpi-nixos

NixOS configurations for a small Raspberry Pi fleet, covering audio receivers, UPS monitoring, local time services, and ADS-B reception. This is the device side of [home-lab](https://github.com/kelchm/home-lab), maintained with the same SOPS and mise tooling.

## Design

Hosts compose shared hardware support, service roles, and optional profiles. The same role can run on different boards or share a host with another role. Hardware support comes from [nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi), while host userspace follows a separate stable nixpkgs input.

## Repository structure

- [hosts/](hosts/) — host configurations and role composition.
- [modules/](modules/) — shared configuration, board support, service roles, and profiles.
- [pkgs/](pkgs/) — packages maintained locally for the fleet.
- [secrets/](secrets/) — encrypted host configuration.
- [flake.nix](flake.nix) and [flake.lock](flake.lock) — system definitions and pinned dependencies.
- [.github/](.github/) — CI checks and dependency-update automation.

## Documentation

- [Architecture](docs/architecture.md) — configuration model, configured hosts, and shared identities.
- [Setup and operations](docs/operations.md) — prerequisites, deployment, provisioning, recovery, and key management.
- [Observability](docs/observability.md) — metrics, logs, resource limits, and verification.
- [Time services](docs/time-services.md) — server and client configuration, access policy, and validation.
- [Platform and dependency maintenance](docs/platform-and-updates.md) — upstream choices, updates, build checks, and hardware caveats.

Operational details live in these guides and the host configurations. Deployment results and investigations belong in the relevant issues and pull requests.
