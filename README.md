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
    pi-zero-2w.nix                 nvmd raspberry-pi-02.base + display-vc4 + sd-image + RPi OS brcmfmac options
    wifi-recovery.nix              escalating self-heal for a wedged wlan0 (supplicant → driver reload → reboot)
    pi5.nix                        nvmd raspberry-pi-5.base + display-vc4 + sd-image
  roles/
    streamer.nix                   PipeWire (systemWide) + shairport-sync + the pipewire-group fix
    ups.nix                        NUT (upsd + upsmon); adds pi-nut metrics on enrolled hosts
  profiles/
    debug.nix                      opt-in: HDMI autologin + persistent journal (import on hosts being debugged)
    metrics.nix                    opt-in: loopback node-exporter + vmagent, SOPS token, bounded push queue
hosts/
  <hostname>/
    default.nix                    imports hardware + role + optional profiles; sets hostname-specific bits
    secrets.nix                    optional — host-specific sops declarations
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

## Enroll a Pi in metrics

Import `../../modules/profiles/metrics.nix` in `hosts/<hostname>/default.nix`, then add `metrics-ingest-token` to `secrets/<hostname>.yaml` with `sops`. The profile declares the secret itself; no per-host metrics configuration or `secrets.nix` is needed. Keep any existing secrets in the payload. It is enabled in the configurations for `ups-compute-rack`, `ups-office`, and `streamer-basement-workbench`.

Before deploying, create the matching token key and `VMUser` in home-lab's `kubernetes/apps/observability/metrics-ingest/app/` as described in its [host-monitoring runbook](https://github.com/kelchm/home-lab/blob/main/docs/runbooks/host-monitoring.md). Use a distinct random token for each host and store the same value in both repos. VMAuth must stamp `instance=<hostname>` and `platform=pi`. The configured hosts use `UPS_COMPUTE_RACK_TOKEN`, `UPS_OFFICE_TOKEN`, and `STREAMER_BASEMENT_WORKBENCH_TOKEN` in home-lab; their tokens are already encrypted in this repo. The Pi supplies no identity labels. These tokens inherit the existing shared-fleet-key trust model: any Pi holding that key can decrypt the other Pis’ tokens. Add `pi-node`, `pi-vmagent`, and `pi-nut` to home-lab's existing host-alert and Hosts-dashboard selectors before relying on coverage, and include `wl` interfaces in its network panels for WiFi-only Pis; subsequent Pis need no new selector changes.

The host needs `/var/lib/sops-nix/host-key.txt` before activation can decrypt its token. Follow the fleet-key bootstrap below for a new or reflashed host. On an existing host that has never consumed secrets, securely install the decrypted fleet key there as root with mode `0600` before the first metrics deployment. The two UPS hosts previously had no SOPS payloads, so check with `ssh kelchm@<hostname>.local sudo test -s /var/lib/sops-nix/host-key.txt` during their rollout. If missing, install the existing fleet key (do not rotate it):

```sh
age -d -i "$SOPS_AGE_KEY_FILE" fleet.age | \
  ssh kelchm@<hostname>.local 'sudo install -d -m 0700 /var/lib/sops-nix && sudo install -m 0600 /dev/stdin /var/lib/sops-nix/host-key.txt'
```

The profile runs node-exporter on `127.0.0.1:9100` and vmagent on `127.0.0.1:8429`. Every 30 seconds, vmagent scrapes `pi-node` and `pi-vmagent`, then pushes to `https://metrics-ingest.home.kelch.io/api/v1/write`. The root-only token is passed through a systemd credential, outside the Nix store. Editing the encrypted token and deploying restarts vmagent to refresh that credential; coordinate rotation with home-lab.

### Role-specific collectors

Roles enable a stock exporter on loopback and append a job to `services.vmagent.prometheusConfig.scrape_configs`. Nix merges the job lists, so the base profile needs no edits. See `modules/roles/ups.nix`: when vmagent is enabled, it adds the NUT exporter on `127.0.0.1:9199` and a `pi-nut` job with one `/ups_metrics?ups=<name>` target per entry in `power.ups.ups`. The target's `ups` label identifies the device even if its scrape fails. NUT telemetry reads are anonymous, so the exporter does not use `monuser`; the existing monitor-password TODO remains.

### Memory and SD storage

The base services have systemd memory ceilings of 96 MiB for vmagent and 48 MiB for node-exporter (144 MiB total); the UPS role adds a 32 MiB ceiling for the NUT exporter. vmagent uses one remote-write worker, a 16 MiB internal memory budget, a 48 MiB Go soft limit and `MemoryHigh=64M`. These are resource limits, not measured working sets. The workbench Pi Zero 2 W has been enrolled with this unchanged profile; long-term memory use and WiFi outage behavior still need observation.

The two Pi 5 UPS hosts explicitly add `cgroup_enable=memory` to their kernel parameters. Their DTBs supply `cgroup_disable=memory`, and the generated `cmdline.txt` follows those bootargs, so the later override enables enforcement after reboot. The [Raspberry Pi kernel explanation](https://github.com/raspberrypi/linux/issues/6980) covers the ordering and cgroup v2 checks. Verify that `memory` appears in `/sys/fs/cgroup/cgroup.controllers`, that `systemctl show vmagent -p MemoryCurrent -p MemoryMax` reports numeric usage and `MemoryMax=100663296`, and that `/proc/cmdline` places the enable after the disable. A configured `MemoryMax` alone does not prove enforcement. The streamer already has the memory controller and needs no override.

In a 185-second live observation on 2026-10-18 with AirPlay playback, vmagent used 23.2–26.9 MiB and node-exporter 21.9–22.9 MiB of cgroup memory; their peaks since boot were 28.6 and 23.7 MiB respectively. At least 244 MiB remained available. Neither metrics nor audio services restarted, no cgroup memory-limit/OOM events occurred, and playback was audibly clean. vmagent's process and queue write counters stayed at zero; the whole SD device wrote 32 KiB during the window. This short healthy-network check does not predict long outages or long-term SD wear.

The persistent queue lives at `/var/cache/vmagent/remote_write_tmp`. Its pending-data limit is 1,073,741,824 bytes (1 GiB), matching the other enrolled hosts. Reserve about 2 GiB on the SD filesystem for backlog, retained chunk files and metadata. Oldest data is discarded at capacity. Raising this allowance does not increase normal healthy-delivery writes; it permits more samples to survive an outage. At the workbench streamer’s observed rate of about 780 B/s, 1 GiB represents roughly 16 days of backlog, but actual retention depends on the workload. The limit bounds backlog, not cumulative writes or outage duration.

Healthy delivery normally buffers in RAM. An outage spills to disk, and shutdown flushes pending samples; sudden power loss can lose the RAM buffer. Thirty-second scrapes keep collection modest, and journald stays in RAM. The profile adds `psi=1` because the vendor kernel disables pressure accounting by default; reboot after first enrollment for `node_pressure_*` metrics and memory-stall alerts. After enrollment, compare `MemoryCurrent` and `MemoryPeak` with `systemctl show vmagent prometheus-node-exporter` (also `prometheus-nut-exporter` on UPS hosts), queue writes with `rate(vm_persistentqueue_bytes_written_total{job="pi-vmagent"}[1h])`, and actual SD traffic with `rate(node_disk_written_bytes_total{job="pi-node",device="mmcblk0"}[1h])`. A queue-size limit alone does not protect the card from frequent outages.

### Service probes

Only `ups-compute-rack` imports `hosts/ups-compute-rack/probes.nix`. It runs the stock blackbox exporter on `127.0.0.1:9115` and appends `pi-blackbox` and `pi-blackbox-exporter` through the metrics profile’s native scrape configuration. Nine HTTP, TCP, DNS and ICMP probes run every 60 seconds with five-second timeouts. The ingestion token supplies the host identity; `target`, `probe` and `module` distinguish destinations. The other Pis have no probe service or jobs.

The exporter has a 32 MiB Go soft limit, `MemoryHigh=48M` and `MemoryMax=64M`. Verify the memory controller before relying on the systemd limits. Probe targets, expected unauthenticated responses, alert ownership and the Pushover drill are documented in home-lab’s [host-monitoring runbook](https://github.com/kelchm/home-lab/blob/main/docs/runbooks/host-monitoring.md#service-probes).

### Verify after deployment

Build with `nix flake check --accept-flake-config` and `nix build .#nixosConfigurations.<hostname>.config.system.build.toplevel --accept-flake-config`; the stock vmagent module checks the rendered scrape config with `-dryRun` during the build. After deployment, run `ssh kelchm@<hostname>.local curl -s 127.0.0.1:8429/targets`, then query the store:

```promql
up{platform="pi",instance="ups-compute-rack"}
network_ups_tools_ups_status{instance="ups-compute-rack",flag="OB"}
network_ups_tools_battery_runtime{instance="ups-compute-rack"}
```

Expect `pi-node` and `pi-vmagent` on every enrolled Pi and `pi-nut` on UPS hosts. Runtime is reported in seconds only when the UPS driver supplies it. Replace the instance for another host; no scrape-config edit is needed.

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
- **brcmfmac options**: nvmd doesn't ship Raspberry Pi OS's `rpi-brcmfmac.conf` (`roamoff=1 feature_disable=0x282000`), so the chip firmware handled roaming and once left the streamer off Wi-Fi for 13 days with the OS still up. `pi-zero-2w.nix` sets the options; `wifi-recovery.nix` is the safety net and writes a snapshot to `/var/log/wifi-recovery/` before each recovery step. The `feature_disable` bits shift between kernels, so re-check it on kernel bumps.
- **AirPlay 2** on the streamer is blocked on putting the Pi on the same L2 subnet as the AirPlay source. Cross-subnet PTP doesn't reach nqptp. Reverted to AP1, which works.
- **`services.shairport-sync` + `services.pipewire.systemWide`** don't auto-wire the shairport user into the `pipewire` group. Silent EACCES on the PipeWire socket otherwise. We add it manually in `modules/roles/streamer.nix`. NixOS integration gap.
- **shairport-sync config restart**: NixOS doesn't restart the daemon when only its `/etc/shairport-sync.conf` changes (the unit file is unchanged). We add an explicit `restartTriggers` in the streamer role so deploys reliably re-read the config.
- **Mac builder VM** defaults to 1 core / 3 GB. Bump it (I use 6 cores / 8 GB) in nix-darwin config or SD image builds take forever.
- **linux-builder substituter trust**: the flake's `nixConfig` substituters apply only to the Mac evaluator, NOT the linux-builder VM's nix-daemon. The VM needs `nixos-raspberrypi.cachix.org` in *its* nix.conf — set via `nix.linux-builder.config.nix.settings.extra-substituters` in nix-darwin. Without it, the VM rebuilds Pi kernels from source instead of fetching them.
