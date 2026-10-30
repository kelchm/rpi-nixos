{ config, lib, ... }:
let
  # Active infrastructure and client VLANs. Guest, RemoteAdmin and reserved
  # networks are excluded; gateway access is a separate deployment step.
  clients = map (vlan: "10.32.${toString vlan}.0/24") [ 1 5 10 20 21 25 30 90 ];
in
{
  services.chrony = {
    enable = true; # The NixOS module also disables systemd-timesyncd.
    # Pi 5's RTC lacks the update interrupts needed by chrony's RTC driver.
    # Preserve kernel RTC updates instead of using rtcfile/rtcautotrim.
    enableRTCTrimming = false;
    servers = [ "192.168.100.1" ];
    extraConfig = ''
      # Up to four public peers cross-check the best-effort dish.
      pool 0.nixos.pool.ntp.org iburst maxsources 4
      # No prefer/trust or NTS requirement: the dish can work alone if WAN
      # sources disappear. Omit local; normal holdover is still possible.
      minsources 1
      leapsecmode system
      rtcsync
      cmdport 0
      ${lib.concatMapStringsSep "\n" (net: "allow ${net}") clients}
    '';
  };

  # Match chrony's ACL at the host firewall; no IPv6 or public NTP listener
  # is admitted. NixOS owns and flushes this chain when reloading the rules.
  networking.firewall.extraCommands = lib.concatMapStringsSep "\n" (net:
    "iptables -A nixos-fw -p udp -s ${net} --dport 123 -j nixos-fw-accept"
  ) clients;
  assertions = [
    {
      assertion = config.networking.firewall.enable && config.networking.firewall.backend == "iptables";
      message = "The NTP server's source-scoped rules require the NixOS iptables firewall.";
    }
  ];

  services.prometheus.exporters.chrony = lib.mkIf config.services.vmagent.enable {
    enable = true;
    listenAddress = "127.0.0.1";
    openFirewall = false;
    # The stock module uses chrony's local Unix socket, even with cmdport 0.
    # Avoid reverse DNS during a scrape, especially when WAN access is lost.
    enabledCollectors = [ "tracking" "sources" "sources.with-ntpdata" "serverstats" ];
    disabledCollectors = [ "dns-lookups" ];
  };
  systemd.services.prometheus-chrony-exporter = lib.mkIf config.services.vmagent.enable {
    after = [ "chronyd.service" ];
    wants = [ "chronyd.service" ];
    # The exporter creates a reply socket beside chronyd's command socket.
    serviceConfig.ReadWritePaths = [ "/run/chrony" ];
  };
  services.vmagent.prometheusConfig.scrape_configs = lib.mkIf config.services.vmagent.enable [
    {
      job_name = "pi-chrony";
      static_configs = [ { targets = [ "127.0.0.1:9123" ]; } ];
    }
  ];
}
