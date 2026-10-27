{ config, lib, pkgs, sources, ... }:
{
  # Import to send the journal to home-lab's VictoriaLogs. It reuses the
  # metrics profile's token, so identity again comes from VMAuth, and the
  # metrics profile's vmagent scrapes the collector.
  imports = [ ../metrics.nix ];

  sops.secrets.metrics-ingest-token.restartUnits = [ "fluent-bit.service" ];

  services.fluent-bit = {
    enable = true;
    package = pkgs.callPackage ../../../pkgs/fluent-bit.nix { inherit (sources.fluent-bit) src version; };
    # Both files in one store directory: the config names host.lua relative
    # to itself.
    configurationFile = "${lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [ ./fluent-bit.yaml ./host.lua ];
    }}/fluent-bit.yaml";
    # Leaves 10 s past the config's 30 s grace to flush, as home-lab does.
    graceLimit = 40;
  };

  systemd.services.fluent-bit = {
    requires = [ "sops-install-secrets.service" ];
    after = [ "sops-install-secrets.service" ];
    serviceConfig = {
      # Root-only source; systemd copies it for the DynamicUser.
      LoadCredential = [ "metrics-ingest-token:${config.sops.secrets.metrics-ingest-token.path}" ];
      # /run/fluent-bit holds the cursor and buffer. Keep it across restarts so
      # a redeploy resumes from the cursor; a reboot clears it with the journal.
      RuntimeDirectory = "fluent-bit";
      RuntimeDirectoryMode = "0700";
      RuntimeDirectoryPreserve = true;
      # tmpfs pages count against the service, so this covers the 16 MiB
      # buffer as well as the process.
      MemoryHigh = "48M";
      MemoryMax = "64M";
    };
  };

  services.vmagent.prometheusConfig.scrape_configs = [
    {
      job_name = "pi-fluent-bit";
      metrics_path = "/api/v2/metrics/prometheus";
      static_configs = [ { targets = [ "127.0.0.1:2020" ]; } ];
    }
  ];
}
