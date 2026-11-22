# Ritornel player

`streamer-basement-workbench` runs a [Ritornel](https://github.com/ritornel/ritornel) player beside its AirPlay receiver. The [Ritornel player role](../modules/roles/ritornel-player.nix) runs `ritornel-server` as a satellite of a hub that holds the library: the Pi pulls each track it plays from the hub, plays it through the streamer role's PipeWire and USB DAC, and sends its listens back to the hub. Any host that imports the streamer role can import this one too.

## Build

[`pkgs/ritornel.nix`](../pkgs/ritornel.nix) makes two builds from one source. The server is built with `--no-default-features --features audio-output`: sound through ALSA, no Last.fm, no media session. `ritornelctl` is built with its defaults. Rust comes from the source's `rust-toolchain.toml` through [rust-overlay](https://github.com/oxalica/rust-overlay), since Ritornel usually needs a newer rustc than the host channel has. The test suite is skipped; Ritornel's own CI runs it on arm64.

## Service

`ritornel.service` runs `ritornel-server serve --data-dir /var/lib/ritornel --output default` as the `ritornel` system user, which is in the `pipewire` group to reach the system PipeWire socket. It starts after PipeWire and WirePlumber and restarts ten seconds after a failure. It does not wait for the network, because the server starts without its hub and finds it once it answers. With no `--listen`, the server stays on loopback and the role opens no firewall port.

Sound goes through ALSA's `default` device into PipeWire, whose only sink is the USB DAC: the streamer role disables the Pi's headphone jack and keeps the DAC's hardware volume at 0 dB across reboots and replugs. Ritornel's volume is its own gain, independent of the AirPlay slider.

The hub is reached by its `.local` name, which needs Avahi with nss-mdns (`common.nix` enables both).

The data directory is mode 0700 and the client proves itself by reading it, so the `ritornelctl` installed on the host is a wrapper that runs the real client as `ritornel` against `/var/lib/ritornel`. Over SSH, `ritornelctl status`, `ritornelctl play` and the rest work as they are.

## Joining the hub

A data directory joins its hub once. The link lives in `/var/lib/ritornel/server.db`, so it survives deploys, rollbacks and reboots, but not a reflash or a deleted data directory.

1. On the hub, make an invite with `ritornelctl link invite`. It is valid once, for ten minutes, and holds a secret after `#`. Never put it in the Nix store, SOPS, or this repository.
2. On the Pi, within those ten minutes: `ritornelctl link join '<invite>' --data-dir /var/lib/ritornel`.
3. Check with `ritornelctl link status` on either side.

The hub refuses a satellite that speaks another contract version, and the refusal says which side is older.

## State and SD-card writes

| Path | Contents | Retention |
|---|---|---|
| `/var/lib/ritornel/server.db` | The hub link, player, queue, and listens waiting for the hub | Kept |
| `/var/lib/ritornel/cache/audio` | Each master pulled whole from the hub before it plays | Until the server evicts it |
| `/var/lib/ritornel/logs/` | The server's own JSON-line log, one file a day | Never pruned |

The server's log is written to the SD card, outside the journal, which stays in RAM. Count it with the cache and the database when looking at card wear (`node_disk_written_bytes_total`, see [observability](observability.md#memory-and-sd-storage)), and delete old log files by hand if they pile up.

## Updates

The `ritornel` flake input is pinned to one commit. A satellite and its hub must share Ritornel's contract version, so move the pin only together with the hub: edit the commit in `flake.nix` and run `nix flake lock`. A commit in the URL keeps Renovate's lock maintenance from moving it, and Dependabot is not allowed to. `rust-overlay` is refreshed by lock maintenance, which leaves the pinned toolchain version unchanged.

## Validate after deployment

Deploy with the normal [test-then-switch procedure](operations.md#day-to-day-deploys), then on the Pi:

```sh
systemctl is-active ritornel pipewire wireplumber shairport-sync
ritornelctl status
ritornelctl link status
sudo -u ritornel env PIPEWIRE_RUNTIME_DIR=/run/pipewire speaker-test -D default -c 2 -t sine -l 1
```

`speaker-test` as the service user proves the path from ALSA's `default` through PipeWire to the DAC without Ritornel. While a track plays, `ritornelctl now` shows the rate the output opened at, and `pw-top` shows the stream beside any AirPlay session.
