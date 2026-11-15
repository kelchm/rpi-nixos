{ config, lib, pkgs, ... }:
let
  # One private network for this container. No decoder ports are published.
  bridge = "ufbr0";
  gateway = "172.30.109.1";
  address = "172.30.109.2";
  networkFile = pkgs.writeText "ultrafeeder-network.json" (builtins.toJSON {
    name = "ultrafeeder";
    id = builtins.hashString "sha256" "rpi-nixos-ultrafeeder";
    driver = "bridge";
    network_interface = bridge;
    subnets = [ { subnet = "172.30.109.0/29"; inherit gateway; } ];
    ipv6_enabled = false;
    internal = false;
    dns_enabled = false;
    ipam_options.driver = "host-local";
  });
  # Bind before Podman creates the bridge. Distinct ports also avoid piaware's
  # MLAT listener, which may listen on all host addresses at port 30105.
  relays = {
    beast = { listen = 39005; target = 30005; };
    mlat = { listen = 39015; target = 30105; };
  };
  iptables = lib.getExe' config.networking.firewall.package "iptables";
  installIngress = pkgs.writeShellScript "ultrafeeder-ingress-install" ''
    set -eu
    ${iptables} -w -t raw -N ultrafeeder-ingress 2>/dev/null || true
    ${iptables} -w -t raw -C ultrafeeder-ingress ! -i ${bridge} -d ${address}/32 -j DROP 2>/dev/null || \
      ${iptables} -w -t raw -A ultrafeeder-ingress ! -i ${bridge} -d ${address}/32 -j DROP
    ${iptables} -w -t raw -C PREROUTING -j ultrafeeder-ingress 2>/dev/null || \
      ${iptables} -w -t raw -I PREROUTING -j ultrafeeder-ingress
  '';
  removeIngress = pkgs.writeShellScript "ultrafeeder-ingress-remove" ''
    ${iptables} -w -t raw -D PREROUTING -j ultrafeeder-ingress 2>/dev/null || true
    ${iptables} -w -t raw -F ultrafeeder-ingress 2>/dev/null || true
    ${iptables} -w -t raw -X ultrafeeder-ingress 2>/dev/null || true
  '';
in
{
  assertions = [
    {
      assertion = config.services.dump1090-fa.enable;
      message = "The Ultrafeeder role needs the existing ADS-B receiver role.";
    }
    {
      assertion = config.networking.firewall.enable && config.networking.firewall.backend == "iptables";
      message = "The Ultrafeeder bridge ingress rule requires an enabled iptables firewall.";
    }
  ];

  sops.secrets = {
    receiver-altitude.sopsFile = ../../secrets + "/${config.networking.hostName}.yaml";
    ultrafeeder-uuid.sopsFile = ../../secrets + "/${config.networking.hostName}.yaml";
  };

  environment.etc."containers/networks/ultrafeeder.json".source = networkFile;
  networking.firewall.interfaces.${bridge}.allowedTCPPorts =
    map (relay: relay.listen) (lib.attrValues relays);
  # Netavark enables routing. Reject packets addressed directly to the
  # container from outside its bridge, even if a LAN client adds a route.
  # Raw PREROUTING runs before DNAT, so replies to masqueraded outbound feed
  # connections still arrive addressed to the host and are unaffected.
  # Never flush or remove this guard during a host firewall reload/stop.
  # Cleanup follows container removal instead, when nothing remains exposed.
  networking.firewall.extraCommands = "${installIngress}";

  systemd.sockets = lib.mapAttrs' (name: relay:
    lib.nameValuePair "ultrafeeder-${name}" {
      description = "Ultrafeeder ${name} connection to the host";
      wantedBy = [ "sockets.target" ];
      listenStreams = [ "${gateway}:${toString relay.listen}" ];
      socketConfig = {
        FreeBind = true;
        NoDelay = true;
      };
    }
  ) relays;

  systemd.services = (lib.mapAttrs' (name: relay:
    lib.nameValuePair "ultrafeeder-${name}" {
      description = "Relay ${name} to the existing ADS-B receiver";
      serviceConfig = {
        ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd 127.0.0.1:${toString relay.target}";
        DynamicUser = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    }
  ) relays) // {
    podman-ultrafeeder = {
      requires = [ "sops-install-secrets.service" ];
      after = [ "sops-install-secrets.service" "dump1090-fa.service" ];
      wants = [ "ultrafeeder-beast.socket" "ultrafeeder-mlat.socket" ];
      restartTriggers = [ networkFile ];
      preStart = "${installIngress}";
      postStop = lib.mkAfter "${removeIngress}";
      serviceConfig = {
        StateDirectory = [ "ultrafeeder/history" "ultrafeeder/graphs" ];
        # Bound registry/network failures during activation; a failed pull is
        # retried after RestartSec without disturbing the native receiver.
        TimeoutStartSec = lib.mkForce "5min";
        RestartSec = 30;
      };
    };
  };

  sops.templates."ultrafeeder.env" = {
    content = ''
      READSB_LAT=${config.sops.placeholder.receiver-latitude}
      READSB_LON=${config.sops.placeholder.receiver-longitude}
      READSB_ALT=${config.sops.placeholder.receiver-altitude}
      UUID=${config.sops.placeholder.ultrafeeder-uuid}
    '';
    restartUnits = [ "podman-ultrafeeder.service" ];
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers.ultrafeeder = {
      # Pin the multi-platform manifest; Podman selects the native ARM64 image.
      image = "ghcr.io/sdr-enthusiasts/docker-adsb-ultrafeeder:latest@sha256:ed8a1395ad666d792d23e5306e468d12e91ff7b5a2c435fe8ff1868bbb7e3be5";
      environmentFiles = [ config.sops.templates."ultrafeeder.env".path ];
      networks = [ "ultrafeeder" ];
      environment = {
        TZ = config.time.timeZone;
        LOGLEVEL = "error";
        READSB_NET_ONLY = "true";
        READSB_RX_LOCATION_ACCURACY = "1";
        READSB_MAX_RANGE = "360";
        READSB_STATS_RANGE = "true";
        # Keep returned positions in the MLAT hub, separate from radio uploads.
        # --privacy requests omission of this station from public MLAT maps.
        ULTRAFEEDER_CONFIG = lib.concatStringsSep ";" [
          "adsb,${gateway},39005,beast_in"
          "mlathub,${gateway},39015,beast_in"
          "adsb,in.adsb.lol,30004,beast_reduce_plus_out"
          "mlat,in.adsb.lol,31090,--privacy"
          "adsb,feed.airplanes.live,30004,beast_reduce_plus_out"
          "mlat,feed.airplanes.live,31090,--privacy"
        ];
        MLAT_USER = "kelchm-office";
        MLATHUB_ENABLE = "true";
        UPDATE_TAR1090 = "false";
        TAR1090_PAGETITLE = "Office aircraft";
        TAR1090_SITENAME = "Office receiver";
        TAR1090_ENABLE_AC_DB = "true";
        # Import the actual radio's signal/adaptive-gain statistics, rather
        # than showing the network-only readsb instance as the radio.
        URL_1090_SIGNAL = "http://${gateway}:8080";
        MAX_GLOBE_HISTORY = "7";
        READSB_ENABLE_TRACES = "true";
        GRAPHS1090_REDUCE_IO = "true";
        GRAPHS1090_REDUCE_IO_FLUSH_IVAL = "6h";
      };
      volumes = [
        "/var/lib/ultrafeeder/history:/var/globe_history"
        "/var/lib/ultrafeeder/graphs:/var/lib/collectd"
      ];
      extraOptions = [
        "--ip=${address}"
        "--tmpfs=/run:rw,exec,nosuid,size=256m"
        "--tmpfs=/var/log:rw,nosuid,size=32m"
        "--memory=512m"
        "--memory-swap=512m"
        "--shm-size=64m"
      ];
    };
  };

  # Nginx provides the LAN-facing port; Podman publishes no host ports.
  services.nginx.virtualHosts.ultrafeeder = {
    listen = [ { addr = "0.0.0.0"; port = 8081; } ];
    locations."/".proxyPass = "http://${address}:80";
    extraConfig = "access_log off;";
  };
  networking.firewall.allowedTCPPorts = [ 8081 ];
}
