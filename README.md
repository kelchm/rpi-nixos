# rpi-nixos

NixOS configurations for my Raspberry Pi fleet. Companion to [home-lab](https://github.com/kelchm/home-lab) (the k8s side of things); same sops mental model, same mise tooling.

This is **specific to my setup** — hostnames, WiFi network, hardware, location. Borrow patterns; don't expect the configs themselves to drop in.

## Status

| Host | Hardware | Role | State |
|---|---|---|---|
| `streamer-basement-workbench` | Pi Zero 2 W | AirPlay receiver → PipeWire → USB DAC | Running |
| `ups-compute-rack` | Pi 5 | NUT server for the compute rack's UPS | Running |
| `ups-office` | Pi 5 | NUT server for the office UPS (Liebert PSA5, Starlink + T-Mobile gateways) | In progress |
| `ups-network-rack` | Pi 5 | NUT server for the network rack's UPS | Planned |
| `streamer-*` (more) | Pi 5 (PoE-able) or Pi Zero 2 W | More AirPlay receivers | Planned |
| `uconsole` | ClockworkPi uConsole (CM4 or CM5) | Personal handheld | Planned |

## Hardware rule of thumb

PoE available → Pi 5. No PoE / wall-wart appliance → Pi Zero 2 W (2.4 GHz WiFi only).

## Upstream

Everything on [`nvmd/nixos-raspberrypi`](https://github.com/nvmd/nixos-raspberrypi). Reasons:

- `nix-community/raspberry-pi-nix` is archived (March 2025) and hangs Pi 5 boot on nixos-25.05+ with a `vc4-drm bcm2712_iommu_of_xlate` kernel panic.
- nvmd is the maintained community fork. Covers Pi 02/3/4/5 + CM4/CM5, ships a working Cachix at `nixos-raspberrypi.cachix.org`, and the uConsole flake builds on top of it.
- I tried per-board fragmentation (stock sd-image for Pi Zero 2 W, nvmd for Pi 5) and the version-skew pain in a single flake was worse than the bus-factor of one community fork.

**Pin discipline:** tagged release only, never `main`. Currently `v1.20260317.0` (the pin nixos-uconsole uses; `v1.20260517.0` broke CM4 display and got reverted).

Worth revisiting when BCM2712 PCIe + RP1 patches land in mainline (~6.19–6.21) — at that point stock-everywhere becomes viable.

## Layout

```
flake.nix                          one mkHost helper, three hosts today
flake.lock
.sops.yaml                         user + fleet recipients, glob creation rule
.mise.toml                         pins sops + age; sets SOPS_AGE_KEY_FILE
age.key                            user master age private key — gitignored, mirrored in 1Password
fleet.age                          shared fleet age private key, encrypted to the user master (committed)
secrets/
  <hostname>.yaml                  per-host sops payload, encrypted to user + fleet
modules/
  common.nix                       Nix settings, GC, timezone, locale, zram, mDNS, base packages
  sops-host-key.nix                early-boot service: install fleet key from FIRMWARE
  users.nix                        admin user + authorized keys
  ssh.nix                          OpenSSH hardening
  hardware/
    pi-zero-2w.nix                 nvmd raspberry-pi-02.base + display-vc4 + sd-image
    pi5.nix                        nvmd raspberry-pi-5.base + display-vc4 + sd-image
  roles/
    streamer.nix                   PipeWire (systemWide) + shairport-sync + the pipewire-group fix
    ups.nix                        NUT (upsd + upsmon) in standalone mode
  profiles/
    debug.nix                      opt-in: HDMI autologin + persistent journal (import on hosts being debugged)
hosts/
  <hostname>/
    default.nix                    imports hardware + role; sets hostname-specific bits
    secrets.nix                    optional — only present if this host consumes sops secrets
```

## Naming

Hostnames are `<role>-<location>`. Role first so `ssh <role>-<tab>` lists all hosts of that role.

- `streamer-basement-workbench`, `streamer-office`
- `ups-compute-rack`, `ups-office`, `ups-network-rack`
- `uconsole` (one-off, no role prefix needed)

Display names (the string in AirPlay pickers, etc.) are separate and free-form English. The streamer above is "Basement Workbench Speakers" in Music.app. Set in the per-host `default.nix` via the role's relevant option.

## Secrets

Two age keys total, one user-controlled and one fleet-shared:

1. **User master** (`./age.key`, gitignored, mirrored in 1Password). The root of trust. mise sets `SOPS_AGE_KEY_FILE` to it when you `cd` in.
2. **Fleet shared** (`./fleet.age`, encrypted to the user master, committed). One key planted on every Pi at `/var/lib/sops-nix/host-key.txt`. Every `secrets/*.yaml` is encrypted to both user + fleet, via a single glob rule in `.sops.yaml`.

Trade-off accepted: a compromised SD card exposes all fleet secrets, not just that host's. Acceptable for a small homelab; matches the cluster-key pattern in `home-lab`. If per-host isolation ever matters, the model refactors to one key per host without changing the rest of the architecture.

On first boot the fleet key gets moved from the FAT32 FIRMWARE partition (where the operator placed it on the Mac before flashing) to `/var/lib/sops-nix/host-key.txt` via `modules/sops-host-key.nix`. It survives reboots but not reflashes — the bootstrap step has to be redone each flash.

Decrypted values land at `/run/secrets/<name>` (root:root 0400); sops-nix templates render to `/run/secrets-rendered/<name>`.

Edit a secret:

```sh
sops secrets/<hostname>.yaml
```

## Prerequisites

- macOS dev machine with [Nix installed](https://github.com/NixOS/experimental-nix-installer).
- [nix-darwin](https://github.com/nix-darwin/nix-darwin) configured with `nix.linux-builder.enable = true` (aarch64-linux builds happen in the Apple Virtualization VM).
- [mise](https://mise.jdx.dev/) (`brew install mise`).
- `age.key` from 1Password placed at `./age.key` (mode 0600).
- 1Password SSH agent loaded with the SSH key listed in `modules/users.nix`.

## Initial setup after clone

```sh
cd rpi-nixos
mise install                            # gets sops + age at pinned versions, sets SOPS_AGE_KEY_FILE

# get age.key from 1Password ("sops age key — rpi-nixos") and put it here:
cat > age.key                           # paste, ctrl-D
chmod 600 age.key

# sanity check
sops -d secrets/streamer-basement-workbench.yaml
```

## Day-to-day deploys

For a running host:

```sh
nix run github:NixOS/nixpkgs/nixpkgs-unstable#nixos-rebuild -- switch \
  --flake .#<hostname> \
  --target-host kelchm@<hostname>.local \
  --sudo \
  --accept-flake-config
```

Builds on the Mac's linux-builder VM, ships only the diff to the Pi, activates. ~1–3 min for a config tweak.

## Add or reflash a host

Same flow either way. Sops works on first boot because the fleet key is on the SD card before the Pi ever runs.

1. **(New host only) create the host module.**
   - `hosts/<hostname>/default.nix` — imports the hardware module (`modules/hardware/pi-zero-2w.nix` or `pi5.nix`), the role module(s), and `./secrets.nix` if the host consumes any sops secrets. Set `system.stateVersion = "25.11"` (matches nvmd's pinned nixpkgs).
   - `hosts/<hostname>/secrets.nix` (only if the host has secrets) — declares `sops.secrets.*` and any `sops.templates.*`. No `sops.age.*` boilerplate; that lives centrally in `modules/sops-host-key.nix`.
   - `secrets/<hostname>.yaml` — `sops secrets/<hostname>.yaml` to create + encrypt. The `secrets/*.yaml` glob in `.sops.yaml` auto-encrypts to user + fleet.
   - Add `<hostname> = mkHost { ... }` to `flake.nix`.

2. **Build the SD image:**
   ```sh
   nix build .#nixosConfigurations.<hostname>.config.system.build.sdImage --accept-flake-config
   ```

3. **Flash it:**
   ```sh
   diskutil list                                                        # find the SD card device
   diskutil unmountDisk /dev/diskN
   zstdcat result/sd-image/*.img.zst | sudo dd of=/dev/rdiskN bs=4m
   diskutil eject /dev/diskN                                            # eject so we can re-mount
   ```
   Re-insert the card so macOS auto-mounts the FAT32 FIRMWARE partition at `/Volumes/FIRMWARE`.

4. **Plant the fleet key on FIRMWARE** (skip if the host has no secrets):
   ```sh
   age -d -i "$SOPS_AGE_KEY_FILE" -o /Volumes/FIRMWARE/sops-host-key fleet.age
   diskutil eject /dev/diskN
   ```

5. **Insert into the Pi, power on.** First boot: the early-boot service moves the FIRMWARE key to `/var/lib/sops-nix/host-key.txt`, sops-nix decrypts, WiFi (if any) associates from the rendered supplicant config, host is reachable at `<hostname>.local`.

After that, routine config changes are plain `nixos-rebuild --target-host`. No key handling, no second rebuild.

Reflash is identical — the fleet key on FIRMWARE matches what's already in the repo, secrets decrypt fine, no `.sops.yaml` edits needed. The Pi's SSH host key rotates on reflash but isn't load-bearing for sops anymore.

### When to reflash vs. deploy

Reflash is rarely needed. Almost everything (new packages, service config tweaks, even new kernel versions) goes through `--target-host`. Real reasons to reflash:

- First install of a new host.
- Switching upstream flakes (e.g., the move from `raspberry-pi-nix` to nvmd). Technically live-doable but kernel + firmware + bootloader all change at once and it's safer to start fresh.
- Recovering from a bricked rebuild.

### Rotating the fleet key

Generate fresh, push to every running host, redeploy:

```sh
USER_RECIPIENT="$(age-keygen -y "$SOPS_AGE_KEY_FILE")"
KEYDATA="$(age-keygen 2>/dev/null)"
echo "new fleet recipient: $(printf '%s\n' "$KEYDATA" | grep -oE 'age1[a-z0-9]+' | head -1)"
printf '%s\n' "$KEYDATA" | age -r "$USER_RECIPIENT" -o fleet.age

# update .sops.yaml &fleet anchor to the new recipient, then:
sops updatekeys secrets/*.yaml

# push new key to each running host:
for h in <hostname1> <hostname2>; do
  age -d -i "$SOPS_AGE_KEY_FILE" fleet.age | \
    ssh kelchm@$h "sudo tee /var/lib/sops-nix/host-key.txt >/dev/null && \
                   sudo chmod 0600 /var/lib/sops-nix/host-key.txt"
done

# then nixos-rebuild --target-host each
```

## Known quirks

- **Workbench IPv6 discovery** is disabled in its host config: Thread border routers on Main and Guest announce the same on-link IPv6 prefix, but the Pi is reachable from Main only over IPv4. Avahi uses IPv4 announcements with `publish-aaaa-on-ipv4=no` so AirPlay clients do not select an unreachable IPv6 address. Remove both settings only after cross-VLAN IPv6 reachability is established. This does not fix the separate Tailscale route/firewall path to Guest.
- **AirPlay 2** on the streamer is blocked on putting the Pi on the same L2 subnet as the AirPlay source. Cross-subnet PTP doesn't reach nqptp. Reverted to AP1, which works.
- **`services.shairport-sync` + `services.pipewire.systemWide`** don't auto-wire the shairport user into the `pipewire` group. Silent EACCES on the PipeWire socket otherwise. We add it manually in `modules/roles/streamer.nix`. NixOS integration gap.
- **shairport-sync config restart**: NixOS doesn't restart the daemon when only its `/etc/shairport-sync.conf` changes (the unit file is unchanged). We add an explicit `restartTriggers` in the streamer role so deploys reliably re-read the config.
- **Mac builder VM** defaults to 1 core / 3 GB. Bump it (I use 6 cores / 8 GB) in nix-darwin config or SD image builds take forever.
- **linux-builder substituter trust**: the flake's `nixConfig` substituters apply only to the Mac evaluator, NOT the linux-builder VM's nix-daemon. The VM needs `nixos-raspberrypi.cachix.org` in *its* nix.conf — set via `nix.linux-builder.config.nix.settings.extra-substituters` in nix-darwin. Without it, the VM rebuilds Pi kernels from source instead of fetching them.
