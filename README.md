# rpi-nixos

NixOS configurations for the Raspberry Pi fleet — one flake, one upstream, one
secret-management approach across all hosts. Companion to
[home-lab](https://github.com/kelchm/home-lab) (the k8s side of things).

This repo is **specific to my setup** — hostnames, WiFi network, hardware,
location. Borrow patterns freely; the configs themselves won't be useful as a
template.

## Status

| Host | Hardware | Role | State |
|---|---|---|---|
| `streamer-basement-workbench` | Pi Zero 2 W | AirPlay receiver → PipeWire → USB DAC | Running |
| `ups-compute-rack` | Pi 5 | NUT server for the compute rack's UPS | In bring-up |
| `ups-network-rack` | Pi 5 | NUT server for the network rack's UPS | Planned |
| `streamer-*` (more) | Pi 5 (PoE racks) or Pi Zero 2 W (elsewhere) | More AirPlay receivers | Planned |
| `uconsole` | ClockworkPi uConsole (CM4 or CM5) | Personal handheld | Planned |

## Hardware choice rules

- **PoE available** → Pi 5 (rack switches, etc.)
- **No PoE / appliance** → Pi Zero 2 W (USB wall adapter; 2.4 GHz WiFi only)

## Upstream choice

**Everything is on [`nvmd/nixos-raspberrypi`](https://github.com/nvmd/nixos-raspberrypi).**

Why this is the only flake input for Pi hardware:

- `nix-community/raspberry-pi-nix` is **archived as of March 2025** and breaks
  Pi 5 boot on nixos-25.05+ (`vc4-drm bcm2712_iommu_of_xlate` kernel hang)
- `nvmd/nixos-raspberrypi` is the actively-maintained community fork, covers
  Pi 02 / 3 / 4 / 5 + CM4 / CM5, ships a working Cachix
  (`nixos-raspberrypi.cachix.org`), and the uConsole flake builds on top of it
- We tried per-board fragmentation (stock sd-image for Pi Zero 2 W, nvmd for
  Pi 5) — the version-skew pain in a single flake was worse than the bus-factor
  risk of a single community fork

**Pin discipline**: tagged release only, never `main`. Current pin
`v1.20260317.0` (matches the pin nixos-uconsole uses; `v1.20260517.0` broke
CM4 display and was reverted upstream).

When BCM2712 PCIe + RP1 patches make it into mainline Linux (~6.19–6.21),
this decision is worth revisiting — we could go stock-everywhere.

## Repository layout

```
flake.nix                          one mkHost helper, two hosts today
flake.lock
.sops.yaml                         age recipients per host (user + per-host)
age.key                            (gitignored) the personal age private key — also in 1Password
.mise.toml                         pins sops, age; sets SOPS_AGE_KEY_FILE
fleet.age                          shared fleet age private key, encrypted to the user recipient (committed)
                                   — single key dropped on every Pi at install; matches home-lab's
                                   sops model. Fleet pubkey lives in .sops.yaml as the &fleet anchor.
secrets/
  <hostname>.yaml                  sops-encrypted, per host (recipients: user + that host)
modules/
  common.nix                       Nix settings, GC, timezone, locale, zram, mDNS, base packages
  sops-host-key.nix                early-boot service: install host age key from FIRMWARE on first boot
  users.nix                        admin user + authorized keys
  ssh.nix                          OpenSSH hardening
  hardware/
    pi-zero-2w.nix                 nvmd raspberry-pi-02.base + display-vc4 + sd-image
    pi5.nix                        nvmd raspberry-pi-5.base + display-vc4 + sd-image
  roles/
    streamer.nix                   PipeWire (systemWide) + shairport-sync + the pipewire-group fix
    ups.nix                        NUT (upsd + upsmon) in standalone mode
hosts/
  <hostname>/
    default.nix                    imports hardware + role + secrets; sets hostname-specific bits
    secrets.nix                    (optional) sops secrets/templates — only if this host consumes any
```

## Naming convention

Hostnames are `<role>-<location>`. Role first so `ssh <role>-<tab>` lists all
hosts of that role. Examples:

- `streamer-basement-workbench`
- `streamer-office`
- `ups-compute-rack`
- `ups-network-rack`
- `uconsole` (no role needed, one-off)

Display names (what shows up in AirPlay pickers, etc.) are separate and
freeform English — e.g., the streamer hostname above is "Basement Workbench
Speakers" in iOS / Music.app. Set via the role's relevant option in the
per-host `default.nix`.

## Secrets

- **Your personal age key** is the root of trust. Kept in 1Password as
  "sops age key — rpi-nixos"; working copy at `./age.key` (gitignored, mode
  0600). mise sets `SOPS_AGE_KEY_FILE` to it when you `cd` into the repo.
- **One shared fleet age key**, committed as `./fleet.age` (encrypted to the
  user master). Every host gets this same key dropped on its FIRMWARE at
  install. The fleet public key is the `&fleet` anchor in `.sops.yaml`; every
  `secrets/*.yaml` is encrypted to `user + fleet`. Trade-off accepted: a
  compromised SD card would expose all fleet secrets, not just that host's
  — acceptable for a small homelab, matches the cluster-key pattern used
  in `home-lab`. If we ever want per-host isolation later, the model
  refactors to per-host keys without changing the rest of the architecture.
- Each Pi gets its host private key planted on the SD card's FIRMWARE
  partition before first boot. `modules/sops-host-key.nix` relocates it to
  `/var/lib/sops-nix/host-key.txt` on first boot and removes the FIRMWARE
  copy. After that, sops-nix uses it for every decrypt — survives reboots,
  doesn't survive reflash unless re-placed on FIRMWARE.
- `.sops.yaml` has one creation rule per host, listing the user and that
  host's recipient as the age keys.
- Decrypted secrets land at `/run/secrets/<name>` (root:root 0400);
  sops-nix templates render to `/run/secrets-rendered/<name>`.

To edit secrets:

```sh
sops secrets/<hostname>.yaml
```

## Prerequisites

- macOS dev machine with [Nix installed](https://github.com/NixOS/experimental-nix-installer)
- [nix-darwin](https://github.com/nix-darwin/nix-darwin) configured with
  `nix.linux-builder.enable = true` (Pi builds happen in the Apple
  Virtualization VM)
- [mise](https://mise.jdx.dev/) (`brew install mise`)
- The `age.key` file from 1Password placed at `./age.key`
- 1Password SSH agent loaded with the SSH key authorized in `modules/users.nix`

## Initial setup after clone

```sh
cd rpi-nixos
mise install                       # gets sops + age at pinned versions, sets SOPS_AGE_KEY_FILE

# get age.key from 1Password ("sops age key — rpi-nixos") and put it here:
# (or symlink from wherever you store it)
cat > age.key                      # paste, ctrl-D
chmod 600 age.key

# sanity check
sops -d secrets/streamer-basement-workbench.yaml
```

## Day-to-day deploy

For an existing, running host, almost everything is `--target-host`:

```sh
nix run github:NixOS/nixpkgs/nixpkgs-unstable#nixos-rebuild -- switch \
  --flake .#streamer-basement-workbench \
  --target-host kelchm@streamer-basement-workbench.local \
  --sudo \
  --accept-flake-config
```

This builds the new system closure on the Mac's linux-builder VM, ships only
the diff to the Pi, and activates. Typical wall-clock: 1–3 min for a config
tweak.

## When to reflash (rare)

Building + flashing an SD image is needed only for:

1. **First install** of a brand-new host
2. **Switching upstream flakes** (e.g., we did this when moving from
   `raspberry-pi-nix` to `nvmd/nixos-raspberrypi`) — technically doable live
   but the kernel + firmware + bootloader all change at once
3. **Recovery from a bricked rebuild**

For everything else (new kernel version, new initrd modules, new packages,
service config tweaks), `--target-host` is faster and preserves state.

### How to reflash

```sh
# Build the SD image
nix build .#nixosConfigurations.<hostname>.config.system.build.sdImage \
  --accept-flake-config

# Identify the SD card (be careful)
diskutil list

# Flash (replace diskN with the actual SD card device)
diskutil unmountDisk /dev/diskN
zstdcat result/sd-image/*.img.zst | sudo dd of=/dev/rdiskN bs=4m
sync && diskutil eject /dev/diskN
```

## Add or reflash a host

Same flow whether you're standing up a brand-new Pi or reflashing an
existing one. WiFi or wired — doesn't matter. Sops works on first boot
because the **shared fleet key** is on the SD card before it ever runs.

1. **Create the host module** (skip on reflash):

   - `hosts/<hostname>/default.nix` — imports the hardware module
     (`modules/hardware/pi-zero-2w.nix` or `pi5.nix`), the role module(s),
     and `./secrets.nix` if the host has any secrets. Set
     `system.stateVersion = "25.11"` (matches nvmd's pinned nixpkgs).
   - `hosts/<hostname>/secrets.nix` (only if the host has secrets) —
     declares `sops.secrets.*` and any `sops.templates.*`. No `sops.age.*`
     boilerplate; that's handled centrally by `modules/sops-host-key.nix`.
   - `secrets/<hostname>.yaml` (only if the host has secrets) —
     `sops secrets/<hostname>.yaml` to create and encrypt values. The
     `.sops.yaml` `creation_rules` glob `secrets/*.yaml` automatically
     encrypts to `user + fleet`.

   Add `<hostname> = mkHost { ... }` to `flake.nix`.

2. **Build the SD image:**

   ```sh
   nix build .#nixosConfigurations.<hostname>.config.system.build.sdImage \
     --accept-flake-config
   ```

3. **Flash it:**

   ```sh
   diskutil list                              # find the SD card device
   diskutil unmountDisk /dev/diskN
   zstdcat result/sd-image/*.img.zst | sudo dd of=/dev/rdiskN bs=4m
   diskutil eject /dev/diskN                  # eject so we can re-mount
   ```

   Now re-insert the SD card so macOS auto-mounts the FAT32 FIRMWARE
   partition at `/Volumes/FIRMWARE`.

4. **Plant the fleet key on FIRMWARE:**

   ```sh
   age -d -i "$SOPS_AGE_KEY_FILE" -o /Volumes/FIRMWARE/sops-host-key fleet.age
   diskutil eject /dev/diskN
   ```

   Skip this step entirely if the host has no secrets (e.g., a wired Pi 5
   that doesn't consume any sops-managed values yet — it'll boot and be
   reachable without needing decryption).

5. **Insert into the Pi and power on.** First boot:
   - The early-boot service moves `/boot/firmware/sops-host-key` to
     `/var/lib/sops-nix/host-key.txt` and removes the FIRMWARE copy.
   - sops-nix decrypts every secret addressed via the fleet key.
   - WiFi (if any) associates from the rendered supplicant config.
   - The Pi is reachable at `<hostname>.local` (mDNS) or whatever IP
     DHCP assigns it.

After this, routine config changes use `nixos-rebuild --target-host` — no
key handling, just plain deploys.

### Reflash specifics

Reflashing is identical — same fleet key gets dropped, same secrets
decrypt. No `.sops.yaml` edits, no `updatekeys`, no second rebuild. The
SSH host key rotates on reflash but it's no longer load-bearing for sops
decryption.

### One-time setup: generating fleet.age

The fleet key is generated once and committed (encrypted to your user
master). To re-generate (rotation, compromise recovery):

```sh
USER_RECIPIENT="$(age-keygen -y "$SOPS_AGE_KEY_FILE")"
KEYDATA="$(age-keygen 2>/dev/null)"
FLEET_PUBKEY="$(printf '%s\n' "$KEYDATA" | grep -oE 'age1[a-z0-9]+' | head -1)"
printf '%s\n' "$KEYDATA" | age -r "$USER_RECIPIENT" -o fleet.age
echo "New fleet recipient: $FLEET_PUBKEY"
# 1. Update .sops.yaml &fleet anchor
# 2. sops updatekeys secrets/*.yaml
# 3. Push new fleet key to every running host:
#    age -d -i "$SOPS_AGE_KEY_FILE" fleet.age | \
#      ssh kelchm@<host> 'sudo tee /var/lib/sops-nix/host-key.txt >/dev/null && \
#        sudo chmod 0600 /var/lib/sops-nix/host-key.txt'
# 4. nixos-rebuild --target-host to each
```

## Known follow-ups / quirks

- **AirPlay 2** on the streamer is blocked on the Pi being on the same L2
  subnet as the AirPlay source (cross-subnet PTP doesn't reach nqptp).
  Reverted to AP1, which works. See
  `~/.claude/projects/-Users-kelchm-Development-kelchm-rpi-nixos/memory/project_airplay2_pending.md`.
- **`services.shairport-sync` + `services.pipewire.systemWide` doesn't
  auto-wire the shairport user into the `pipewire` group** — silent EACCES on
  the PipeWire socket otherwise. We add it manually in
  `modules/roles/streamer.nix`. Documented as a NixOS integration gap.
- **Mac builds**: the Apple Virtualization linux-builder VM defaults to 1 core
  / 3 GB. Bump it to something realistic (we use 6 cores / 8 GB; could go
  higher on an M-series Mac) in your nix-darwin config to stop SD image builds
  taking forever.
