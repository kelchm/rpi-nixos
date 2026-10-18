{ config, lib, pkgs, ... }:
{
  # NUT (Network UPS Tools) server. Per-host config declares the specific UPS
  # under `power.ups.ups.<name>` and the upsmon monitor entry pointing at it.
  #
  # Scope: standalone mode, listens on the LAN so other hosts can query
  # telemetry (reads are anonymous in NUT — no auth needed for upsc).
  # The monuser password is a placeholder; it only matters when we add
  # secondary upsmon hosts for coordinated shutdown, at which point migrate
  # to sops-nix.
  power.ups = {
    enable = true;
    mode = "standalone";
    upsd.listen = [
      { address = "0.0.0.0"; port = 3493; }
      { address = "::"; port = 3493; }
    ];

    # NUT requires upsmon, and upsmon requires a user to log in to upsd as.
    # Placeholder password — only consequential once we add upsmon secondaries
    # or expose this to less-trusted networks. TODO: sops-manage when either.
    users."monuser" = {
      passwordFile = "${pkgs.writeText "ups-poc-monuser-pw" "poc-placeholder"}";
      upsmon = "primary";
    };
  };

  networking.firewall.allowedTCPPorts = [ 3493 ];

  environment.systemPackages = with pkgs; [ nut ];

  # Adding this role to an enrolled host adds its collector without changing
  # the metrics profile. NUT's LIST commands are anonymous; no monuser needed.
  services.prometheus.exporters.nut = lib.mkIf config.services.vmagent.enable {
    enable = true;
    listenAddress = "127.0.0.1";
    openFirewall = false;
    nutServer = "127.0.0.1";
    # v3.2.2's built-in list omits runtime even though the NixOS option says
    # an empty list exports everything. Include it explicitly for UPS alerts.
    nutVariables = [
      "battery.charge"
      "battery.charge.low"
      "battery.runtime"
      "battery.runtime.low"
      "battery.voltage"
      "battery.voltage.nominal"
      "input.voltage"
      "input.voltage.nominal"
      "ups.load"
      "ups.status"
    ];
  };
  systemd.services.prometheus-nut-exporter = lib.mkIf config.services.vmagent.enable {
    serviceConfig.MemoryMax = "32M";
  };
  services.vmagent.prometheusConfig.scrape_configs = lib.mkIf config.services.vmagent.enable [
    {
      job_name = "pi-nut";
      metrics_path = "/ups_metrics";
      # One target per UPS, also works when a future Pi has several USB UPSes.
      static_configs = map (ups: {
        targets = [ "127.0.0.1:9199" ];
        labels = { inherit ups; };
      }) (builtins.attrNames config.power.ups.ups);
      relabel_configs = [
        { source_labels = [ "ups" ]; target_label = "__param_ups"; }
      ];
    }
  ];
}
