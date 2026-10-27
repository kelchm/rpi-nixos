{ config, lib, pkgs, ... }:
let
  tcllauncher = pkgs.callPackage ../../pkgs/tcllauncher.nix { };
  mlat-client = pkgs.callPackage ../../pkgs/mlat-client.nix { };
  piaware = pkgs.callPackage ../../pkgs/piaware.nix { inherit tcllauncher mlat-client; };

  sopsFile = ../../secrets + "/${config.networking.hostName}.yaml";
  inherit (config.sops) placeholder;
in
{
  # ADS-B receiver feeding FlightAware: dump1090-fa decodes the RTL-SDR, piaware
  # uploads to FlightAware and runs MLAT, nginx serves the local SkyAware map.
  # Per-host, in the host's sops payload: the feeder ID and the antenna's
  # coordinates. The repo is public, so the location never goes in Nix.

  # Blacklists the DVB-T driver that would otherwise claim the dongle, and adds
  # the plugdev udev rule the dump1090-fa service uses for USB access.
  hardware.rtl-sdr.enable = true;

  sops.secrets = {
    piaware-feeder-id = { inherit sopsFile; };
    receiver-latitude = { inherit sopsFile; };
    receiver-longitude = { inherit sopsFile; };
  };

  sops.templates = {
    # The only setting that differs from piaware's defaults (receiver-type
    # rtlsdr on localhost:30005, MLAT on, results back to dump1090 on 30104,
    # remote updates off). Keeping the ID keeps the site's stats and history.
    "piaware.conf" = {
      content = ''
        feeder-id ${placeholder.piaware-feeder-id}
      '';
      path = "/etc/piaware.conf";
      owner = "piaware";
      restartUnits = [ "piaware.service" ];
    };
    # dump1090 uses the receiver location for local position decoding and the
    # map's range rings. systemd substitutes these into its arguments.
    "dump1090-location.env" = {
      content = ''
        LAT=${placeholder.receiver-latitude}
        LON=${placeholder.receiver-longitude}
      '';
      restartUnits = [ "dump1090-fa.service" ];
    };
  };

  # Upstream's defaults (debian/dump1090-fa.default), with the network
  # listeners kept on loopback. Adaptive gain starts at maximum and backs off
  # until the noise floor leaves enough dynamic range, so a dongle with a
  # built-in amplifier, like the Pro Stick, doesn't sit in overload.
  services.dump1090-fa = {
    enable = true;
    extraArgs = [
      "--quiet"
      "--device-type"
      "rtlsdr"
      "--gain"
      "60"
      "--adaptive-range"
      "--fix"
      "--max-range"
      "360"
      "--json-location-accuracy"
      "1"
      "--net-bind-address"
      "127.0.0.1"
      "--lat"
      "\${LAT}"
      "--lon"
      "\${LON}"
    ];
  };

  systemd.services.dump1090-fa = {
    requires = [ "sops-install-secrets.service" ];
    after = [ "sops-install-secrets.service" ];
    serviceConfig = {
      EnvironmentFile = config.sops.templates."dump1090-location.env".path;
      # The nixpkgs module isolates the service from the network entirely;
      # piaware and its MLAT client need its loopback ports.
      PrivateNetwork = lib.mkForce false;
      # The nixpkgs unit never restarts, and dump1090 exits when the dongle
      # drops off USB. Upstream's debian/dump1090-fa.service policy.
      Restart = "on-failure";
      RestartSec = 30;
      RestartPreventExitStatus = 64;
    };
  };

  users.users.piaware = {
    isSystemUser = true;
    group = "piaware";
  };
  users.groups.piaware = { };

  # Mirrors upstream's scripts/piaware.service.
  systemd.services.piaware = {
    description = "FlightAware ADS-B uploader";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    requires = [ "sops-install-secrets.service" ];
    after = [
      "dump1090-fa.service"
      "network-online.target"
      "time-sync.target"
      "sops-install-secrets.service"
    ];
    # piaware pings the watchdog through systemd-notify from PATH; without it
    # WatchdogSec would kill a healthy uploader.
    path = [ config.systemd.package ];
    serviceConfig = {
      ExecStart = "${lib.getExe piaware} -p %t/piaware/piaware.pid -plainlog -statusfile %t/piaware/status.json";
      User = "piaware";
      Group = "piaware";
      RuntimeDirectory = "piaware";
      # Feeder state FlightAware sends back, e.g. the site location.
      CacheDirectory = "piaware";
      Restart = "on-failure";
      RestartSec = 30;
      # 4: login failed; 6: bad arguments or no MAC address.
      RestartPreventExitStatus = "4 6";
      WatchdogSec = 120;
      WatchdogSignal = "SIGKILL";
      NotifyAccess = "all";
    };
  };

  # SkyAware, laid out like upstream's lighttpd config on port 8080.
  services.nginx = {
    enable = true;
    virtualHosts.skyaware = {
      listen = [
        {
          addr = "0.0.0.0";
          port = 8080;
        }
      ];
      root = "${config.services.dump1090-fa.package}/share/dump1090";
      locations."/data/".alias = "/run/dump1090-fa/";
      # The open map polls aircraft.json every second; keep that off the SD card.
      extraConfig = ''
        access_log off;
      '';
    };
  };
  networking.firewall.allowedTCPPorts = [ 8080 ];
}
