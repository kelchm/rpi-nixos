# 🍓 rpi-nixos

NixOS for the Raspberry Pis around my house. Each one does a job tied to the hardware plugged into it or the spot where it sits: AirPlay speakers on the basement workbench, UPS telemetry in the compute rack and office, local time service, and an ADS-B antenna feeding FlightAware. This is the device-side companion to [home-lab](https://github.com/kelchm/home-lab), my Kubernetes cluster: the Pis run their services locally and report into the cluster's observability stack.

## 📦 What the Pis do

- **AirPlay 2 speakers.** A Pi Zero 2 W on WiFi with a USB DAC turns the workbench speakers into an AirPlay 2 receiver. shairport-sync and nqptp handle the AirPlay 2 session and its timing; PipeWire drives the DAC.
- **UPS telemetry.** Pi 5s connect over USB to the CyberPower UPS feeding the compute rack and the Vertiv Liebert PSA5 carrying the office's Starlink and T-Mobile gateways. Network UPS Tools reads each unit, and battery charge, runtime, load, and input voltage flow to home-lab for alerting.
- **Local time.** The same two Pi 5s serve NTP to the house with chrony, using the Starlink dish and public NTP pool servers as time sources.
- **ADS-B reception.** An RTL-SDR dongle and antenna on the office Pi 5 receive broadcasts from nearby aircraft. dump1090-fa decodes them, piaware feeds FlightAware and participates in multilateration, and SkyAware provides a live aircraft map.
- **Service probes.** The compute-rack Pi checks network and home-lab services, including DNS, identity, and media services, providing a view of their reachability from outside the cluster.
- **Metrics and logs.** Shared profiles collect host and service metrics with vmagent and ship the systemd journal with Fluent Bit. home-lab stores them in VictoriaMetrics and VictoriaLogs for central monitoring and troubleshooting.

The Pis handle the attached equipment and local services; home-lab provides the central metric and log storage, alerts, and dashboards.

## 🧱 How it's built

Each Pi is a complete NixOS system defined in this flake, from kernel and firmware up through its services, users, and SSH policy. The same definition builds a flashable SD image for a new or replaced board, or an update for one already running.

Hosts are assembled from shared modules: board support for the Pi Zero 2 W, Pi 3, and Pi 5; service roles for AirPlay, UPS, NTP, and ADS-B; and profiles for metrics, journal shipping, and debugging. Roles stack, which is how the office Pi 5 runs UPS monitoring, NTP, and ADS-B together.

Board support comes from [nvmd/nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi), pinned to tagged releases along with its cached kernel and firmware, while host userspace follows a stable nixpkgs channel independently. Software the pinned channel lacks or ships too old (shairport-sync and nqptp for AirPlay 2 fixes, the FlightAware stack, and Fluent Bit matched to home-lab's collectors) is packaged in `pkgs/` from pinned upstream releases. Renovate and Dependabot propose updates; CI evaluates every host and checks that a routine OS refresh leaves the kernel and firmware alone.

Settings that shouldn't be public, such as WiFi credentials, the FlightAware feeder ID and antenna location, and metrics ingest tokens, are encrypted per host with [SOPS](https://github.com/getsops/sops) and age, on the same model as home-lab.

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
