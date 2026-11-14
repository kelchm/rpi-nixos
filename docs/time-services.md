# Time services

## Local NTP servers

The wired UPS hosts serve NTP on Infra Mgmt: `ups-compute-rack` at `10.32.20.111` and `ups-office` at `10.32.20.112`. Server configuration lives in [ntp-server.nix](../modules/roles/ntp-server.nix). Gateway policy, DHCP option 42, and client enrollment are managed separately in home-lab.

The shared `ntp-server` role uses stock chrony and disables systemd-timesyncd through the NixOS module, leaving one clock daemon. Its sources are the Starlink dish at `192.168.100.1` and up to four public peers from the NixOS NTP pool. The dish is best effort with no published accuracy guarantee; it has no `prefer` or `trust` override. Ordinary unauthenticated NTP allows the dish to remain usable when the public sources disappear. This trades authentication for that fallback; a sole incorrect dish cannot be cross-checked. `minsources 1` permits one usable source. We omit `local`, which would let the host claim to be a time reference without an upstream; losing all sources still leaves holdover replies while the clock's error estimate grows. The configuration uses normal UTC leap handling, without Google-style leap smear. `rtcsync` preserves the kernel's periodic hardware-clock updates; chrony's own RTC trimming is disabled because the Pi 5 RTC lacks the required update interrupts. See [chrony's source-selection guidance](https://chrony-project.org/faq.html) and the [chrony configuration reference](https://chrony-project.org/doc/4.8/chrony.conf.html).

Only UDP 123 is allowed from Default, Cameras, Main, InfraMgmt, Workloads, Storage, K8sProd and IoT (`10.32.{1,5,10,20,21,25,30,90}.0/24`). Both the host firewall and chrony's ACL enforce that list. Guest, RemoteAdmin, reserved networks and IPv6 clients are excluded. Inter-VLAN gateway rules, DHCP option 42 and Talos clients are separate changes; this role changes none of them. Preserve the existing UniFi WAN2 route to the dish and do not add WAN port forwarding.

The stock chrony exporter listens only on `127.0.0.1:9123`, reads the daemon's Unix socket as the chrony user and disables reverse DNS during scrapes. UDP command port 323 stays disabled. The existing vmagent adds `job="pi-chrony"`; VMAuth supplies the existing `instance` and `platform="pi"` identity. No new token is needed. Central alert rules are maintained in home-lab.

When changing the server configuration, use the normal [deployment procedure](operations.md#day-to-day-deploys) with `test` before `switch`, one Pi at a time. Use the fixed management IPs if `.local` does not resolve. Record the old system path for rollback, and inspect the effective service changes before activating. Enabling the role replaces timesyncd with chronyd and adds its exporter and scrape job. Other activation effects depend on the diff; do not assume an unrelated UPS service restart or reboot is required. A host behind main may inherit earlier changes too; compare its running closure before activation. Chrony's stock startup policy permits clock steps over 100 ms during its first three updates; confirm the existing clock is synchronized first.

On each Pi, check:

```sh
systemctl is-active chronyd prometheus-chrony-exporter vmagent upsd upsdrv upsmon
systemctl is-active systemd-timesyncd # expected: inactive
sudo chronyc waitsync 60 0.1 0 5
sudo chronyc -n tracking
sudo chronyc -n sources -v
curl --fail --silent http://127.0.0.1:9123/metrics | grep -x 'chrony_up 1'
curl --fail --silent http://127.0.0.1:8429/targets
```

Require normal leap status, a selected source, reachable dish and public peers, healthy old collectors and unchanged UPS readings. Check stored `chrony_up`, `chrony_tracking_info`, `chrony_sources_state_info`, `chrony_sources_reachability_ratio` and `chrony_sources_last_sample_age_seconds` for both instances. The estimated system-clock error is `abs(chrony_tracking_system_time_seconds) + chrony_tracking_root_dispersion_seconds + 0.5 * chrony_tracking_root_delay_seconds`; this depends on the upstream clock being correct, and is not a calibrated UTC accuracy measurement. `chronyd -p` parses both rendered configurations in CI without contacting sources or changing a clock.

With an empty driftfile, allow about two minutes for initial frequency estimation before client probes. `waitsync` and a healthy-looking tracking report alone do not prove that clients can use the replies. Verify NTP replies from an allowed client with `chronyd -Q -t 15 'server 10.32.20.111 iburst'`, then `.112`; `-Q` measures offset without setting the client clock.

For an approved [source-group selection check](https://chrony-project.org/doc/4.8/chronyc.html#selectopts), first record `sudo chronyc -n sources -a` and `sudo chronyc -n selectdata -a`; the configured/effective flags should have no `noselect`, `prefer`, `trust` or `require`. Before changing flags, arrange `EXIT` and signal cleanup in the test shell: remove every added `noselect` with `sudo chronyc selectopts <source> -noselect`, using each source's current IP or unresolved `ID#...` identifier from `sources -a`, then run `sudo chronyc online` and `sudo chronyc reselect`, including after an interrupted or failed check. For public-only selection, run `sudo chronyc selectopts 192.168.100.1 +noselect` and `sudo chronyc reselect`. Restore that flag before the dish-only check, which adds `+noselect` to every public source, including unresolved `ID#...` entries, and runs `sudo chronyc reselect` again. In each case require the intended `^*` source, no `^*` or `^+` from the excluded group, advancing `Ref time`, and a successful peer `chronyd -Q` reply; a bounded `sudo chronyc burst 2/4` can obtain fresh measurements. After cleanup, verify the original flags in `selectdata -a`, all sources online in `activity`, and normal selection before persisting.

These operator-controlled checks demonstrate public-only and dish-only usability. They do not measure automatic warm failover timing: [stock chrony may retain a much better unreachable source's measurements for hours](https://chrony-project.org/faq.html#_an_unreachable_source_is_selected), so a short `offline` test need not select a public source. Validate real WAN-outage behavior, other-VLAN client paths, and client failover separately before relying on them. A source-selection check alone does not establish those properties.

If acceptance fails, restore the recorded system with `sudo /nix/store/<previous-system>/bin/switch-to-configuration test` before changing the boot default. If already persisted, use the normal previous-generation rollback. Confirm the previous clock service, UPS monitoring, scrape targets and firewall behavior are restored. Do not change DHCP or other clients while a server remains unaccepted.

## NTP client on the ADS-B fallback

`adsb-office` keeps systemd-timesyncd and lists `10.32.20.111`, `10.32.20.112` and then the four NixOS pool names in `services.timesyncd.servers`. This is a static copy of the DHCP option 42 servers, not an integration: the pinned dhcpcd requests the option, but timesyncd only reads [servers learned by systemd-networkd](https://www.freedesktop.org/software/systemd/man/latest/timesyncd.conf.html), and nixpkgs' dhcpcd installs no timesyncd hook. If option 42 changes, update this list too. The pool sits in `NTP=` because `FallbackNTP=` applies only while no other servers are known, so it stays configured but unused.

timesyncd is a single-source client. It uses the first server that answers usably and moves down the list only when that server times out or is rejected; a reply marked unsynchronized, or a root distance over 5 seconds, counts as rejected. It does not return to an earlier server until the current one fails or the service restarts, so after a Pi or pool failover it can stay on the later source. The UPS hosts run chrony and do not use this list, so there is no time loop.

When bringing the fallback online, first stop piaware on `ups-office` to preserve the [single-feeder constraint](architecture.md#ads-b-receiver-and-fallback). Deploy using the [normal procedure](operations.md#day-to-day-deploys), testing before persisting. Confirm `timedatectl timesync-status` reports normal leap status and one of the two local servers, then check again after a poll interval to verify the packet count is rising. Verify background synchronization without stepping the clock manually.
