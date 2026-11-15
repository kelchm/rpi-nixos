# ADS-B map and community feeds

`ups-office` runs two ADS-B stacks on one radio. The native [ADS-B role](../modules/roles/adsb.nix) owns the RTL-SDR: `dump1090-fa` decodes it, piaware feeds FlightAware and runs FlightAware MLAT, and SkyAware serves the native map. The [Ultrafeeder role](../modules/roles/ultrafeeder.nix) adds an [Ultrafeeder](https://github.com/sdr-enthusiasts/docker-adsb-ultrafeeder) container. It takes the decoder's output over the network and provides tar1090, graphs1090, and ADS-B plus MLAT feeds to [adsb.lol](https://adsb.lol) and [airplanes.live](https://airplanes.live). The fallback `adsb-office` does not import the Ultrafeeder role.

| Port | Served by | Contents |
|---|---|---|
| 8080 | Native nginx and SkyAware | FlightAware's map of the radio's decoder |
| 8081 | Native nginx, proxied to the container | tar1090 map; graphs at `/graphs1090/` |

Both ports are plain HTTP on IPv4 and open to every network that can reach the host.

## Configuration

Nix owns the whole container definition: image, environment, network, mounts, and limits. Settings changed inside the container or through a web UI do not survive a restart. `UPDATE_TAR1090=false` keeps the web interface at the version in the pinned image.

The image is pinned to a digest of its multi-platform manifest; Podman selects the ARM64 image. The container has no USB devices, no host networking, and no published ports. readsb runs in network-only mode, so `dump1090-fa` remains the only process that opens the SDR.

The decoder sends its Beast output from port 30005 to readsb. piaware's FlightAware MLAT results come from port 30105 and go into Ultrafeeder's MLAT hub. Those results are shown on the 8081 map but are not sent to the community feeds. Each community feed runs its own MLAT client, and its results are shown on the map too. Port 8081 also imports the radio's signal and gain statistics from SkyAware's `/data/stats.json` on port 8080, so the graphs describe the real receiver instead of the network-only readsb instance.

## Location and identity

The container reuses the antenna latitude and longitude already stored in the host's SOPS payload. The same payload also holds the antenna elevation and the feed UUID. sops-nix renders these values into a root-only environment file under `/run/secrets-rendered/`, so they never enter the Nix store or this public repository. Keep the UUID unchanged. The aggregators use it to identify this receiver and its statistics.

The aggregators need the exact position and elevation for MLAT. Each MLAT connection passes `--privacy` to request omission from public MLAT sync maps. `receiver-altitude` includes its unit suffix (`m` or `ft`) and uses antenna elevation above mean sea level; the initial value was copied from FlightAware's existing location report. `ultrafeeder-uuid` is shared by the two new feeds and stays separate from the FlightAware feeder ID. Anyone with root access on the Pi can read the values through `podman inspect`.

## Network

The container has its own Podman bridge, `ufbr0`, on `172.30.109.0/29`. The host is the gateway at `172.30.109.1`, and the container is fixed at `172.30.109.2`. Nix writes the network definition to `/etc/containers/networks/ultrafeeder.json`, and netavark creates the bridge when the container starts. Changing the definition restarts the container.

`dump1090-fa` keeps its listeners on loopback. Two socket-activated `systemd-socket-proxyd` relays connect the bridge to those listeners:

| Container connects to | Relay unit | Host target |
|---|---|---|
| `172.30.109.1:39005` | `ultrafeeder-beast` | `127.0.0.1:30005`, decoder Beast output |
| `172.30.109.1:39015` | `ultrafeeder-mlat` | `127.0.0.1:30105`, piaware MLAT results |

The sockets use `FreeBind`, which lets them bind to the gateway address at boot before the bridge exists. The high listening ports also stay clear of piaware's MLAT listener, which may bind every host address on 30105. The host firewall accepts only 39005 and 39015 on `ufbr0`. The container also reaches host port 8080 for radio statistics.

Outbound feed and MLAT traffic leaves through netavark's masquerade rule. Netavark enables IPv4 forwarding when the container starts; removing the bridge does not restore that sysctl. A raw-table ingress rule rejects packets addressed directly to the container from other interfaces, so adding a LAN route through the Pi does not expose its internal ports. Host nginx can still proxy the map. Name resolution uses the host's resolvers. Podman's DNS service is off.

The ingress rule is installed without flushing its chain, so firewall reloads do not create an exposure window. Container startup also installs the guard; cleanup runs only after Podman removes the container, including when the role is removed.

## State and limits

| Path on the host | Contents | Retention |
|---|---|---|
| `/var/lib/ultrafeeder/graphs` | graphs1090 collectd RRD files | Fixed-size round-robin files; flushed from memory every 6 hours |
| `/var/lib/ultrafeeder/history` | Aircraft traces, heatmap/replay data, and readsb state | Trace and heatmap archives are retained for 7 days |
| `/var/lib/containers` | Podman image layers | Until removed with `podman rmi` or `podman system prune` |

Graph data written since the last flush is lost on an unclean stop. Live map files use `/run`; readsb periodically saves its state to the history directory and restores it on restart. Recent changes since the last save can be lost on an unclean stop. Persistent traces add SD-card writes; compare actual device writes after deployment before increasing retention or trace frequency.

The container is limited to 512 MiB of memory with no swap. That limit includes its tmpfs mounts: up to 256 MiB for `/run` and 32 MiB for `/var/log`. Shared memory is capped at 64 MiB. Enforcement relies on the `cgroup_enable=memory` kernel parameter described in [observability](observability.md#memory-and-sd-storage). Runtime CPU, memory, and SD-card writes have not been measured yet.

## Service lifecycle

`podman-ultrafeeder.service` starts after secrets are installed and after `dump1090-fa`. On a first deploy or image update, it pulls the image during startup with a 5-minute start limit. Pull the image on the Pi before activation to avoid that limit on a slow link:

On the Mac, obtain the image reference:

```sh
nix eval --raw .#nixosConfigurations.ups-office.config.virtualisation.oci-containers.containers.ultrafeeder.image
```

On the Pi, run `sudo podman pull <printed-image-reference>`. Podman is installed by this role, so for the first deployment let the service perform the pull. A failed container restarts after 30 seconds. Editing the location, elevation, or UUID in SOPS restarts it on the next deploy. Stopping or restarting the container does not affect `dump1090-fa`, piaware, UPS monitoring, or NTP.

## Validate after deployment

Deploy with the normal [test-then-switch procedure](operations.md#day-to-day-deploys), then check the following on the Pi:

```sh
systemctl is-active dump1090-fa piaware nginx podman-ultrafeeder \
  ultrafeeder-beast.socket ultrafeeder-mlat.socket upsd upsmon chronyd vmagent
ip -4 addr show ufbr0
curl --fail --silent http://127.0.0.1:8081/data/aircraft.json | jq '.aircraft | length'
curl --fail --silent --head http://127.0.0.1:8081/graphs1090/
sudo podman stats --no-stream ultrafeeder
sudo podman logs --since 15m ultrafeeder
sudo podman exec ultrafeeder sh -c 'cat /run/mlat-client/*.json'
journalctl -u piaware --since '15 min ago'
```

The checks pass when:

- Every unit is active, `ufbr0` holds `172.30.109.1`, and the aircraft count roughly matches SkyAware on port 8080.
- The 8081 graphs show the radio's signal and gain rather than empty receiver panels.
- The aggregator check pages show both feeds connected, and each MLAT client's JSON status reports synchronization with nearby receivers. MLAT synchronization can take several minutes. `LOGLEVEL=error` suppresses periodic synchronization log messages, so use the status files rather than waiting for those messages in the journal.
- piaware still reports a FlightAware login and MLAT synchronization.

From a browser on the LAN, open the [adsb.lol feeder check](https://my.adsb.lol) and the [airplanes.live feeder check](https://airplanes.live/myfeed/). Both pages identify the feeder by its public IP.

## Updates

Renovate's custom regex manager tracks the image tag and digest in `modules/roles/ultrafeeder.nix` and proposes digest updates on the normal weekend schedule. CI runs `.github/ci/ultrafeeder-smoke.py` on an ARM64 runner. The test checks the configured production destinations, then substitutes a fake aggregator on an internal Docker network. Synthetic radio and MLAT positions must both appear on the map, while only radio messages may reach the fake aggregator. It also checks the map and graphs endpoints. The trial cannot reach the internet or the real aggregators.

The separate firewall test uses isolated Linux network namespaces and the actual NixOS lifecycle scripts. It verifies that a routed client is blocked before and after a real firewall reload, the host can still reach the container, repeated installation adds no duplicate rules, and cleanup restores the route. CI does not exercise Podman, netavark, or the socket relays; verify those during deployment.

Before merging an image update, read the upstream changes, pull the new image on the Pi, and deploy with `test` before `switch`.

## Rollback

Follow the [rollback procedure](operations.md#rollback-and-hardware-replacement). The previous generation's container definition references its own image digest; if `podman system prune` has removed that image, it is pulled again on start. The state directories survive both rollback and removal of the role. After removing the role, delete `/var/lib/ultrafeeder` and the image by hand if they are no longer wanted. Removing the role stops the community feeds but leaves the native receiver and FlightAware feed unchanged.
