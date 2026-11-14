# Platform and dependency maintenance

The fleet uses Pi 5 boards where wired or PoE operation fits, and Pi Zero 2 W boards (2.4 GHz WiFi only) for small WiFi appliances. Board-specific configuration belongs in `modules/hardware/`; supported host definitions are listed in [architecture](architecture.md#configured-hosts).

## Upstream

All boards use [`nvmd/nixos-raspberrypi`](https://github.com/nvmd/nixos-raspberrypi) for platform support, with a separate stable nixpkgs input for host userspace. Reasons for the shared platform:

- `nix-community/raspberry-pi-nix` is archived (March 2025) and hangs Pi 5 boot on nixos-25.05+ with a `vc4-drm bcm2712_iommu_of_xlate` kernel panic.
- nvmd is the maintained community fork. It covers Pi 02/3/4/5 + CM4/CM5 and supplies cached builds at `nixos-raspberrypi.cachix.org`.
- A shared platform input keeps board support consistent across the fleet while allowing host userspace to follow its own stable channel.

**Platform pin discipline:** tagged release only, never `main`. The current pin is in `flake.nix`; Dependabot proposes newer tags (see [Dependency updates](#dependency-updates)). Host userspace follows `nixos-26.05` independently, with exact revisions recorded in `flake.lock`.

## Dependency updates

- **Routine OS updates:** hosted Renovate refreshes `flake.lock` on weekends. The top-level `nixpkgs` builds every host against `nixos-26.05`; sops-nix follows it. nvmd's tag and its nested nixpkgs stay fixed. Renovate's individual Nix input updates are disabled because its extractor confuses root and nested nixpkgs nodes; lock maintenance runs Nix directly. Renovate also maintains GitHub Actions and mise pins. No updates automerge.
- **Pi platform updates:** Dependabot updates `nixos-raspberrypi`, changing its tag and relocking it in one PR. It checks Sundays at 09:00 UTC with a seven-day cooldown. Review the upstream release notes, then build and boot-test one board family at a time before merging. Kernel fixes still require a platform update; expedite urgent fixes manually when the cooldown is inappropriate. After a manual bump to a release still inside the cooldown, Dependabot proposes the previous release, because it compares commits rather than versions; close that PR.
- **Local packages:** each package in `pkgs/` builds from a flake input pinned to its release tag, and takes its version from that tag. Dependabot proposes new tags on the same schedule but without the cooldown, so a manual bump isn't followed by a downgrade PR. It groups shairport-sync and nqptp in one PR and piaware, tcllauncher and mlat-client in another. If shairport-sync and nqptp disagree on nqptp's shared-memory interface (smiNN), the streamer fails evaluation, so CI catches an incompatible pair. Before merging a FlightAware update, check that piaware_builder pairs the same tcllauncher and mlat-client versions. Keep fluent-bit on the release home-lab's host collectors pin. For an urgent fix, edit the tag in `flake.nix` and run `nix flake lock`.

Passing host `nixpkgs` to nvmd's `lib.nixosSystem` preserves its cached kernel and GPU firmware outputs. Do not set `nixos-raspberrypi.inputs.nixpkgs.follows`: that would change the package set used to build those outputs. `modules/hardware/platform.nix` also retains nvmd's U-Boot and Wi-Fi firmware, giving its firmware higher package priority and first position ahead of generic firmware. CI verifies the resulting files.

**CI** evaluates all four system derivations, parses both rendered chrony configurations, and builds a check that compares the effective merged Wi-Fi firmware with nvmd's files, including compression and symlinks. On `renovate/lock-file-maintenance` PRs it also compares the base and candidate platform snapshots: the OS channel, Pi input, kernels/modules, DTB source, bootloader, U-Boot and Wi-Fi/GPU firmware sources must stay fixed. A failure needs investigation rather than merging a routine refresh as a hardware upgrade.

The initrd, systemd and other userspace still change during OS updates. CI doesn't build whole systems or test hardware. Before merging, build affected hosts and canary the update. On the Wi-Fi-only streamer, use the deploy command with `test` before `switch`; `test` leaves the boot default unchanged. Platform changes additionally need reboot tests on the affected boards. Merging a PR does not deploy it.

NixOS release changes (for example 26.05 → 26.11) are coordinated manual changes to the host channel and a compatible Pi release. A Dependabot Pi tag PR that moves nvmd's nested nixpkgs to a newer release is part of this coordinated change; hold it until the host channel moves too. In `flake.lock`, check `nixos-raspberrypi` → `nixpkgs` → `original.ref`. Keep existing hosts' `system.stateVersion` unchanged.

## Known quirks

- **Audio scope:** the streamer role configures AirPlay 2; Spotify Connect is not configured.
- **Workbench IPv6 discovery** is disabled in its host config: Thread border routers on Main and Guest announce the same on-link IPv6 prefix, but the Pi is reachable from Main only over IPv4. Avahi uses IPv4 announcements with `publish-aaaa-on-ipv4=no` so AirPlay clients do not select an unreachable IPv6 address. Remove both settings only after cross-VLAN IPv6 reachability is established.
- **brcmfmac options**: nvmd doesn't ship Raspberry Pi OS's `rpi-brcmfmac.conf` (`roamoff=1 feature_disable=0x282000`), so firmware roaming needs an explicit override on the streamer. `pi-zero-2w.nix` sets the options; `wifi-recovery.nix` is the safety net and writes a snapshot to `/var/log/wifi-recovery/` before each recovery step. It also reloads the driver whenever the kernel logs `PSM's watchdog has fired`: that firmware fault can leave the interface associated while connectivity fails intermittently. With `roamoff=1` only wpa_supplicant roams, and only with `bgscan`, which the streamer's network block sets. The `feature_disable` bits shift between kernels, so re-check it on kernel bumps.
- **AirPlay 2 across VLANs** needs the sender's PTP (UDP 319/320) to reach nqptp, which never sends first. IPv4 unicast on those ports crosses Main ↔ Guest in both directions. Keep the Pi's IPv6 address out of mDNS (see above), or senders may aim PTP at an address they can't reach.
- **shairport-sync and nqptp are vendored** in `pkgs/` from nixpkgs master, at the tags in `flake.nix`. nixos-26.05's 5.0.4 lacks the pre-auth AirPlay 2 fixes in 5.5+, and 5.6 needs nqptp 1.2.9 (shared-memory interface smi11). Drop both once the release catches up.
- **`services.shairport-sync` + `services.pipewire.systemWide`** don't auto-wire the shairport user into the `pipewire` group. Silent EACCES on the PipeWire socket otherwise. We add it manually in `modules/roles/streamer.nix`. NixOS integration gap.
- **shairport-sync config restart**: NixOS doesn't restart the daemon when only its `/etc/shairport-sync.conf` changes (the unit file is unchanged). We add an explicit `restartTriggers` in the streamer role so deploys reliably re-read the config.
- **Mac builder resources:** configure CPU and RAM for the Linux builder in nix-darwin to suit SD-image and package builds.
- **linux-builder substituter trust**: the flake's `nixConfig` substituters apply only to the Mac evaluator, NOT the linux-builder VM's nix-daemon. The VM needs `nixos-raspberrypi.cachix.org` in *its* nix.conf — set via `nix.linux-builder.config.nix.settings.extra-substituters` in nix-darwin. Without it, the VM rebuilds Pi kernels from source instead of fetching them.
