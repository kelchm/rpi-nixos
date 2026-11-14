# Setup and operations

Run repository commands from the checkout root. Read the [secret model](architecture.md#secret-model) before provisioning a host, and the relevant service guide before activation. Check [platform and update policy](platform-and-updates.md) when changing dependencies or boot components.

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
umask 077
cat > age.key                           # paste, ctrl-D
chmod 600 age.key

# sanity check
sops -d secrets/streamer-basement-workbench.yaml >/dev/null
```

## Day-to-day deploys

For a running host, first record its current system with `readlink -f /run/current-system` on the target Pi and inspect the expected activation changes. A host behind the source branch may inherit unrelated earlier changes; compare its running closure before deploying.

Build, transfer, and test the configuration through the Mac's Linux builder:

```sh
nix run github:NixOS/nixpkgs/nixpkgs-unstable#nixos-rebuild -- test \
  --flake .#<hostname> \
  --target-host kelchm@<hostname>.local \
  --sudo \
  --accept-flake-config
```

Inspect service and network health, then repeat the command with `switch` to persist the boot default. If validation fails, restore the recorded system as described under [rollback](#rollback-and-hardware-replacement).

## Add or reflash a host

Same flow either way. Sops works on first boot because the fleet key is on the SD card before the Pi ever runs.

1. **(New host only) create the host module.**
   - `hosts/<hostname>/default.nix` — imports the hardware module (`modules/hardware/pi-zero-2w.nix`, `pi3.nix` or `pi5.nix`), the role module(s), and optional profiles or host-specific secret declarations. Set `system.stateVersion` to the host's NixOS release at install time (currently "26.05"); never bump it afterwards.
   - `hosts/<hostname>/secrets.nix` is optional for host-specific declarations. Roles and profiles may already declare their own `sops.secrets.*` and `sops.templates.*`; import those modules rather than duplicating their declarations. Shared age-key handling lives in `modules/sops-host-key.nix`.
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

## When to reflash vs. deploy

Reflash is rarely needed. Almost everything (new packages, service config tweaks, even new kernel versions) goes through `--target-host`. Real reasons to reflash:

- First install of a new host.
- Switching upstream flakes (e.g., the move from `raspberry-pi-nix` to nvmd). Technically live-doable but kernel + firmware + bootloader all change at once and it's safer to start fresh.
- Recovering from a bricked rebuild.

## Rotating the fleet key

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

## Editing host secrets

Use `sops secrets/<hostname>.yaml` to edit an encrypted payload. Role and profile declarations select the keys they need. Keep unrelated keys in the payload, and coordinate metrics-token rotation with home-lab. Routine deployments retain the installed fleet key; a reflash requires bootstrapping it again.

## Rollback and hardware replacement

Before persisting a tested configuration, reactivate the recorded system with `sudo /nix/store/<previous-system>/bin/switch-to-configuration test` if validation fails. After changing the boot default, select the previous system generation and restore its boot default as well as its runtime configuration.

A hardware swap needs a clean shutdown before moving an SD card. Preserve the previous system generation and account for the new board's DHCP reservation, power supply, and cooling. Restoring the old board alone does not restore its old software. For ADS-B, keep the [single-feeder rule](architecture.md#ads-b-receiver-and-fallback) in force throughout handoff and rollback.
