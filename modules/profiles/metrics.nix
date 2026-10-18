{ config, ... }:
{
  # Import to enroll a host. Identity comes from its VMAuth token, never from
  # local labels. Roles append to services.vmagent.prometheusConfig.scrape_configs.
  # The vendor kernel compiles PSI in but disables it by default. Host memory
  # stall alerts need node_pressure_*; this takes effect at the next boot.
  boot.kernelParams = [ "psi=1" ];

  sops.secrets.metrics-ingest-token = {
    sopsFile = ../../secrets + "/${config.networking.hostName}.yaml";
    # Keep the source root-only; systemd copies it for vmagent's DynamicUser.
    restartUnits = [ "vmagent.service" ];
  };

  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "127.0.0.1";
    openFirewall = false;
  };

  services.vmagent = {
    enable = true;
    openFirewall = false;
    remoteWrite.url = "https://metrics-ingest.home.kelch.io/api/v1/write";
    # Keep the stock build-time -dryRun check; it does not load auth files.
    checkConfig = true;
    extraArgs = [
      "-httpListenAddr=127.0.0.1:8429"
      "-remoteWrite.bearerTokenFile=%d/metrics-ingest-token"
      # v1.136.0's minimum: (32 MiB + 8 bytes) * 16. Smaller limits round up.
      # This bounds pending data, not total SD writes; allow another ~512 MiB
      # for a partially consumed chunk. The stock service keeps it in /var/cache.
      "-remoteWrite.maxDiskUsagePerURL=536871040"
      "-remoteWrite.queues=1"
      "-memory.allowedBytes=16MiB"
    ];
    prometheusConfig = {
      global = {
        scrape_interval = "30s";
        scrape_timeout = "10s";
      };
      scrape_configs = [
        {
          job_name = "pi-node";
          static_configs = [ { targets = [ "127.0.0.1:9100" ]; } ];
        }
        {
          job_name = "pi-vmagent";
          static_configs = [ { targets = [ "127.0.0.1:8429" ]; } ];
        }
      ];
    };
  };

  systemd.services.vmagent = {
    requires = [ "sops-install-secrets.service" ];
    after = [ "sops-install-secrets.service" ];
    # Leave headroom below MemoryHigh for non-Go memory and queue page cache.
    environment.GOMEMLIMIT = "48MiB";
    serviceConfig = {
      LoadCredential = [ "metrics-ingest-token:${config.sops.secrets.metrics-ingest-token.path}" ];
      MemoryHigh = "64M";
      MemoryMax = "96M";
    };
  };
  systemd.services.prometheus-node-exporter.serviceConfig.MemoryMax = "48M";
}
