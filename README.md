# 🍓 rpi-nixos

NixOS for the Raspberry Pis around my house: small appliances for audio, UPS monitoring, local time, and aircraft reception. This is the device-side companion to [home-lab](https://github.com/kelchm/home-lab), my Kubernetes cluster. The Pis handle attached equipment and local services; home-lab provides central metrics, logs, alerts, and dashboards.

## 🧰 The appliances

The four configurations in this repo combine boards, peripherals, and service roles:

| Appliance | Board used here | Peripherals | Functions |
|---|---|---|---|
| Workbench AirPlay receiver | Pi Zero 2 W (WiFi) | USB DAC and powered speakers | AirPlay 2 audio |
| Compute-rack UPS and time server | Pi 5 (wired) | CyberPower UPS over USB | UPS telemetry, NTP, service probes |
| Office UPS, time server and ADS-B receiver | Pi 5 (wired) | Vertiv Liebert PSA5 over USB; RTL-SDR and antenna | UPS telemetry, NTP, ADS-B |
| Standalone ADS-B fallback | Pi 3 Model B (wired) | Same RTL-SDR and antenna as the office receiver | ADS-B |

All four configurations include metrics collection with vmagent and journal shipping with Fluent Bit to home-lab's VictoriaMetrics and VictoriaLogs. A separate debug profile is available for temporary troubleshooting.

The compute-rack UPS and time server also probes network and home-lab services, providing a view of DNS, identity, and media-service reachability from outside the cluster.

The standalone ADS-B fallback uses the office receiver's SDR, antenna, and FlightAware identity. Only one host may run piaware with that identity at a time. The [architecture guide](docs/architecture.md) maps these appliances to host definitions and explains the fallback constraint.

## 📦 What each role does

- **AirPlay 2.** Makes the workbench speakers available as an AirPlay receiver. shairport-sync and nqptp handle the session and its timing; PipeWire drives the audio output.
- **UPS monitoring.** Network UPS Tools reads battery charge, runtime, load, and input voltage, supplying telemetry for home-lab's power alerts.
- **NTP.** chrony serves local time using the Starlink dish and public NTP pool servers as sources.
- **ADS-B.** dump1090-fa decodes broadcasts from nearby aircraft, piaware feeds FlightAware and participates in multilateration, and SkyAware provides a live aircraft map.

## 🧱 How it's built

Each Pi is a complete NixOS system defined in this flake, from kernel and firmware up through its services, users, and SSH policy. The same definition builds a flashable SD image for a new or replaced board, or an update for one already running.

Board support, service roles, and profiles are shared modules that each host composes.

Board support comes from [nvmd/nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi), pinned to tagged releases, while host userspace follows a stable nixpkgs channel independently. Local packages in `pkgs/` supply AirPlay 2 components, the FlightAware uploader and MLAT client, and Fluent Bit from pinned upstream releases. Renovate and Dependabot propose updates; CI evaluates every host and checks that a routine OS refresh leaves the kernel and firmware alone.

Settings that shouldn't be public, such as WiFi credentials, the FlightAware feeder ID and antenna location, and metrics ingest tokens, are kept in per-host files encrypted with [SOPS](https://github.com/getsops/sops) and age. The Pis decrypt them with one shared fleet key.

Systems are built on a Mac through nix-darwin's Linux builder and deployed manually to each Pi. Merging a change does not deploy it.

## 🗺️ Repository layout

```text
rpi-nixos/
├── hosts/          # one directory per Pi: board, roles, profiles, host-specific settings
├── modules/
│   ├── hardware/   # board support and shared Pi platform policy
│   ├── roles/      # AirPlay, UPS, NTP, and ADS-B services
│   └── profiles/   # metrics, journal shipping, and debugging
├── pkgs/           # packages built from pinned upstream releases
├── secrets/        # SOPS-encrypted per-host settings
├── docs/           # architecture, operations, and maintenance guides
├── .github/        # CI checks and dependency-update automation
└── flake.nix       # host definitions and pinned inputs
```

## 📚 Documentation

- [Architecture](docs/architecture.md) — configuration model, configured hosts, secrets, and what this repo owns versus home-lab.
- [Setup and operations](docs/operations.md) — prerequisites, deployment, provisioning, recovery, and key management.
- [Observability](docs/observability.md) — metrics and journal shipping, service probes, resource limits, and verification.
- [Time services](docs/time-services.md) — the NTP servers, their sources and access policy, and validation.
- [Platform and dependency maintenance](docs/platform-and-updates.md) — upstream choices, update flow, CI checks, and hardware quirks.
