# Architecture

Host configuration is assembled by `mkHost` in [flake.nix](../flake.nix). Shared modules supply the base system, users, SSH, and secret handling; each host then imports its board support, roles, and profiles. Role modules add their own services and monitoring collectors.

## Configured hosts

| Host | Hardware | Roles |
|---|---|---|
| `streamer-basement-workbench` | Pi Zero 2 W | AirPlay receiver through PipeWire and a USB DAC |
| `ups-compute-rack` | Pi 5 | Compute-rack UPS, local NTP, and service probes |
| `ups-office` | Pi 5 | Office UPS, local NTP, and ADS-B receiver |
| `adsb-office` | Pi 3 Model B | ADS-B fallback (normally off) |

The definitions in [hosts/](../hosts/) and [flake.nix](../flake.nix) are authoritative. An existing configuration does not imply that its host is powered on or enrolled as an expected live target in home-lab.

## Modules and packages

- `modules/hardware/` supplies board-specific support and common platform policy.
- `modules/roles/` contains the AirPlay, UPS, NTP, and ADS-B services.
- `modules/profiles/` contains metrics, journal shipping, and optional debugging configuration.
- `pkgs/` supplies packages absent from the pinned nixpkgs or requiring a newer release. Sources and versions are pinned in the flake.

Hostnames use `<role>-<location>`. Display names, such as the AirPlay receiver name, are separate values in the host configuration.

## Secret model

Two age keys total, one user-controlled and one fleet-shared:

1. **User master** (`./age.key`, gitignored, mirrored in 1Password). The root of trust. mise sets `SOPS_AGE_KEY_FILE` to it when you `cd` in.
2. **Fleet shared** (`./fleet.age`, encrypted to the user master, committed). One key planted on every Pi at `/var/lib/sops-nix/host-key.txt`. Every `secrets/*.yaml` is encrypted to both user + fleet, via a single glob rule in `.sops.yaml`.

The shared key means a compromised Pi can decrypt every host payload. This matches home-lab's cluster-key model. Per-host isolation would require replacing the shared fleet key with separate recipients.

On first boot the fleet key gets moved from the FAT32 FIRMWARE partition (where the operator placed it on the Mac before flashing) to `/var/lib/sops-nix/host-key.txt` via [sops-host-key.nix](../modules/sops-host-key.nix). It survives reboots but not reflashes — the bootstrap step has to be redone each flash.

Decrypted values land at `/run/secrets/<name>` (root:root 0400); sops-nix templates render to `/run/secrets-rendered/<name>`.

## ADS-B receiver and fallback

`ups-office` runs `dump1090-fa`, piaware, MLAT, and nginx alongside UPS monitoring and NTP. The [ADS-B role](../modules/roles/adsb.nix) enables adaptive gain, keeps the decoder's network listeners on loopback, and serves SkyAware on port 8080. The feeder ID and antenna coordinates come from the host's encrypted payload; preserving the feeder ID preserves the FlightAware site's statistics and history.

After deployment, check `systemctl status dump1090-fa piaware` and `journalctl -u piaware` for a successful FlightAware login and synchronization with nearby receivers.

The `adsb-office` Pi 3 is a fallback configured with the same feeder ID and should normally remain off. Only one host may run piaware with that identity at a time, even without an SDR attached. Stop piaware on the active host before starting the fallback. Moving an SD card between boards does not change its enabled roles or roll back its software.

## Network and monitoring ownership

Host firewall rules and service listeners live in this repository. Gateway policy, DHCP reservations, central ingestion identities, alert rules, and dashboards live in [home-lab](https://github.com/kelchm/home-lab). Coordinate host retirement or role changes there so an intentional fallback does not become a missing-host alert.

See [time services](time-services.md) for NTP addresses and access policy, and [observability](observability.md) for ingestion and collector configuration.
