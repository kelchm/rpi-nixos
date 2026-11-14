# Observability

The Pi collects locally and pushes to home-lab. Central ingestion stamps host identity from the token; source-side labels are not the trust boundary. Central alerts and dashboards are maintained in home-lab, while this repository owns the producers.

## Enroll a Pi in metrics

Import `../../modules/profiles/metrics.nix` in `hosts/<hostname>/default.nix`, then add `metrics-ingest-token` to `secrets/<hostname>.yaml` with `sops`. The profile declares the secret itself; no per-host metrics configuration or `secrets.nix` is needed. Keep any existing secrets in the payload. All configured hosts import the profile; only hosts intended to run should be expected as live targets in home-lab.

Before deploying, create the matching token key and `VMUser` in home-lab's `kubernetes/apps/observability/metrics-ingest/app/` as described in its [host-monitoring runbook](https://github.com/kelchm/home-lab/blob/main/docs/runbooks/host-monitoring.md). Use a distinct random token for each host and store the same value in both repos. VMAuth must stamp `instance=<hostname>` and `platform=pi`. Configured hosts' tokens are encrypted here; their VMUsers live in home-lab. The Pi supplies no identity labels. These tokens inherit the existing shared-fleet-key trust model: any Pi holding that key can decrypt the other Pis’ tokens. Ensure home-lab's alert and dashboard selectors cover the Pi jobs and include `wl` interfaces for WiFi-only Pis.

The host needs `/var/lib/sops-nix/host-key.txt` before activation can decrypt its token. Follow [host provisioning](operations.md#add-or-reflash-a-host) for a new or reflashed host. On an existing host that has never consumed secrets, securely install the decrypted fleet key there as root with mode `0600` before the first metrics deployment. Before first enrollment, check with `ssh kelchm@<hostname>.local sudo test -s /var/lib/sops-nix/host-key.txt`. If missing, install the existing fleet key (do not rotate it):

```sh
age -d -i "$SOPS_AGE_KEY_FILE" fleet.age | \
  ssh kelchm@<hostname>.local 'sudo install -d -m 0700 /var/lib/sops-nix && sudo install -m 0600 /dev/stdin /var/lib/sops-nix/host-key.txt'
```

The profile runs node-exporter on `127.0.0.1:9100` and vmagent on `127.0.0.1:8429`. Every 30 seconds, vmagent scrapes `pi-node` and `pi-vmagent`, then pushes to `https://metrics-ingest.home.kelch.io/api/v1/write`. The root-only token is passed through a systemd credential, outside the Nix store. Editing the encrypted token and deploying restarts vmagent to refresh that credential; coordinate rotation with home-lab.

### Role-specific collectors

Roles enable a stock exporter on loopback and append a job to `services.vmagent.prometheusConfig.scrape_configs`. Nix merges the job lists, so the base profile needs no edits. See `modules/roles/ups.nix`: when vmagent is enabled, it adds the NUT exporter on `127.0.0.1:9199` and a `pi-nut` job with one `/ups_metrics?ups=<name>` target per entry in `power.ups.ups`. The target's `ups` label identifies the device even if its scrape fails. NUT telemetry reads are anonymous, so the exporter does not use `monuser`; the existing monitor-password TODO remains.

### Memory and SD storage

The base services have systemd memory ceilings of 96 MiB for vmagent and 48 MiB for node-exporter (144 MiB total); the UPS role adds a 32 MiB ceiling for the NUT exporter. vmagent uses one remote-write worker, a 16 MiB internal memory budget, a 48 MiB Go soft limit and `MemoryHigh=64M`. These are resource limits, not measured working sets.

The two Pi 5 UPS hosts explicitly add `cgroup_enable=memory` to their kernel parameters. Their DTBs supply `cgroup_disable=memory`, and the generated `cmdline.txt` follows those bootargs, so the later override enables enforcement after reboot. The [Raspberry Pi kernel explanation](https://github.com/raspberrypi/linux/issues/6980) covers the ordering and cgroup v2 checks. Verify that `memory` appears in `/sys/fs/cgroup/cgroup.controllers`, that `systemctl show vmagent -p MemoryCurrent -p MemoryMax` reports numeric usage and `MemoryMax=100663296`, and that `/proc/cmdline` places the enable after the disable. A configured `MemoryMax` alone does not prove enforcement. The streamer already has the memory controller and needs no override.

The persistent queue lives at `/var/cache/vmagent/remote_write_tmp`. Its pending-data limit is 1,073,741,824 bytes (1 GiB), matching the other enrolled hosts. Reserve about 2 GiB on the SD filesystem for backlog, retained chunk files and metadata. Oldest data is discarded at capacity. Raising this allowance does not increase normal healthy-delivery writes; it permits more samples to survive an outage. Retention depends on each host's sample rate and outage history. The limit bounds backlog, not cumulative writes or outage duration.

Healthy delivery normally buffers in RAM. An outage spills to disk, and shutdown flushes pending samples; sudden power loss can lose the RAM buffer. Thirty-second scrapes keep collection modest, and journald stays in RAM. The profile adds `psi=1` because the vendor kernel disables pressure accounting by default; reboot after first enrollment for `node_pressure_*` metrics and memory-stall alerts. After enrollment, compare `MemoryCurrent` and `MemoryPeak` with `systemctl show vmagent prometheus-node-exporter` (also `prometheus-nut-exporter` on UPS hosts), queue writes with `rate(vm_persistentqueue_bytes_written_total{job="pi-vmagent"}[1h])`, and actual SD traffic with `rate(node_disk_written_bytes_total{job="pi-node",device="mmcblk0"}[1h])`. A queue-size limit alone does not protect the card from frequent outages.

### Service probes

Only `ups-compute-rack` imports `hosts/ups-compute-rack/probes.nix`. It runs the stock blackbox exporter on `127.0.0.1:9115` and appends `pi-blackbox` and `pi-blackbox-exporter` through the metrics profile’s native scrape configuration. Twelve HTTP, TCP, DNS and ICMP probes run every 60 seconds with five-second timeouts. The ingestion token supplies the host identity; `target`, `probe` and `module` distinguish destinations. The other Pis have no probe service or jobs.

The exporter has a 32 MiB Go soft limit, `MemoryHigh=48M` and `MemoryMax=64M`. Verify the memory controller before relying on the systemd limits. Probe targets, expected unauthenticated responses, alert ownership and the Pushover drill are documented in home-lab’s [host-monitoring runbook](https://github.com/kelchm/home-lab/blob/main/docs/runbooks/host-monitoring.md#service-probes).

### Verify after deployment

Build with `nix flake check --accept-flake-config` and `nix build .#nixosConfigurations.<hostname>.config.system.build.toplevel --accept-flake-config`; the stock vmagent module checks the rendered scrape config with `-dryRun` during the build. After deployment, run `ssh kelchm@<hostname>.local curl -s 127.0.0.1:8429/targets`, then query the store:

```promql
up{platform="pi",instance="ups-compute-rack"}
network_ups_tools_ups_status{instance="ups-compute-rack",flag="OB"}
network_ups_tools_battery_runtime{instance="ups-compute-rack"}
```

Expect `pi-node` and `pi-vmagent` on every enrolled Pi, `pi-nut` on UPS hosts, and `pi-chrony` where the time-server role is deployed. Runtime is reported in seconds only when the UPS driver supplies it. Replace the instance for another host; no scrape-config edit is needed.

## Ship the journal

Import `../../modules/profiles/logs` after the metrics profile; it imports that profile itself and reuses its token. The `fluent-bit` service reads the journal, kernel messages included, and sends OTLP to `https://metrics-ingest.home.kelch.io/insert/opentelemetry/v1/logs`. The host's VMUser in home-lab routes that path to VictoriaLogs and stamps `host.name=<hostname>` and `service.namespace=pi`, so the Pi supplies no identity. Fields, queries and alerts are in the "Host logs" section of home-lab's [logging runbook](https://github.com/kelchm/home-lab/blob/main/docs/runbooks/logging.md#host-logs). All configured hosts import it; only running hosts send logs.

Keep `host.lua` synchronized with home-lab's `proxmox/monitoring/logs/host.lua`; update it from there. `fluent-bit.yaml` follows home-lab's and differs only where the Pi forces it: the token is a systemd credential, everything lives in RAM, and reading starts at the head of the journal. nixos-26.05 ships Fluent Bit 5.0.7, so `pkgs/fluent-bit.nix` builds 5.1.5, the version home-lab pins, for its OTLP retry and buffer-limit fixes.

- **RAM only:** it reads only `/run/log/journal`, so journals left on the SD card from before the move to RAM stay unread. Its cursor and its 16 MiB buffer live in `/run/fluent-bit`, the service's runtime directory, which survives restarts and is cleared at boot along with the journal. After a boot it sends the journal from the start; after a restart or deploy it resumes from its cursor. The first deploy sends what journald still holds of the current boot; a busy Pi may already have rotated its earliest entries out of the 16 MiB.
- **Gaps:** lines written after the collector stops at shutdown, or not yet delivered when power is lost, are gone, as is the journal itself. The cursor is saved as each batch is read, so a crash or OOM kill can lose the batch in hand or send part of one twice. A restart keeps the cursor and the buffer, so nothing is lost; a reboot clears whatever is still buffered, such as a backlog from an endpoint outage. Records wait in the buffer while the endpoint is down and arrive with their original timestamps; when the 16 MiB fill, the oldest are dropped. Fluent Bit retries only HTTP 429, 502, 503 and 504, as the OTLP spec says; any other error from the endpoint, such as a 401 for a token it doesn't know or a 500 from VictoriaLogs, drops the batch. home-lab's collectors behave the same.
- **Limits:** `MemoryHigh=48M` and `MemoryMax=64M`. The buffer is tmpfs, so its pages count against these too. Buffer duration depends on log rate. Check drop and retry counters during endpoint outages rather than assuming a fixed retention period.
- **Metrics:** the profile adds a `pi-fluent-bit` job (`127.0.0.1:2020/api/v2/metrics/prometheus`) to vmagent. `fluentbit_output_dropped_records_total{job="pi-fluent-bit"}` should stay 0 and `fluentbit_output_retries_total` flat.
- **Token rotation:** Fluent Bit reads the token only at start. Editing it here restarts both vmagent and `fluent-bit` on the next deploy; coordinate with home-lab as for metrics, and stop `fluent-bit` on the Pi before the old token stops working.
- **Debug profile:** `debug.nix` makes the journal persistent, which moves entries out of `/run/log/journal` early in boot. Shipping stops while a host imports it.

After deploying, check `systemctl status fluent-bit`, then query VictoriaLogs for `host.name:=<hostname> | stats by (service.name) count()` and confirm `host.name:=<hostname> (pipeline.normalize_error:* OR pipeline.severity_unmapped:*)` returns nothing.
