{ pkgs, ... }:
{
  services.prometheus.exporters.blackbox = {
    enable = true;
    listenAddress = "127.0.0.1";
    openFirewall = false;
    configFile = (pkgs.formats.yaml { }).generate "blackbox.yml" {
      modules = {
        http_2xx = {
          prober = "http";
          timeout = "5s";
          http = {
            preferred_ip_protocol = "ip4";
            fail_if_not_ssl = true;
            body_size_limit = "1MB";
          };
        };
        # Kanidm answers /status with HTTP 200 either way; the body says whether it is up.
        http_kanidm_status = {
          prober = "http";
          timeout = "5s";
          http = {
            preferred_ip_protocol = "ip4";
            fail_if_not_ssl = true;
            fail_if_body_not_matches_regexp = [ "^true$" ];
            body_size_limit = "1MB";
          };
        };
        http_redirect = {
          prober = "http";
          timeout = "5s";
          http = {
            preferred_ip_protocol = "ip4";
            valid_status_codes = [ 302 ];
            follow_redirects = false;
            fail_if_not_ssl = true;
            fail_if_header_not_matches = [ { header = "Location"; regexp = "^/login$"; } ];
            body_size_limit = "1MB";
          };
        };
        http_401 = {
          prober = "http";
          timeout = "5s";
          http = {
            preferred_ip_protocol = "ip4";
            valid_status_codes = [ 401 ];
            follow_redirects = false;
            fail_if_not_ssl = true;
            body_size_limit = "1MB";
          };
        };
        tcp_connect = { prober = "tcp"; timeout = "5s"; };
        icmp = { prober = "icmp"; timeout = "5s"; };
        dns_k8s_gateway = {
          prober = "dns";
          timeout = "5s";
          dns = {
            preferred_ip_protocol = "ip4";
            transport_protocol = "udp";
            query_name = "auth.home.kelch.io";
            query_type = "A";
            valid_rcodes = [ "NOERROR" ];
            validate_answer_rrs.fail_if_none_matches_regexp = [
              "^auth\\.home\\.kelch\\.io\\.\\s+\\d+\\s+IN\\s+A\\s+10\\.32\\.140\\.1$"
            ];
          };
        };
      };
    };
  };

  systemd.services.prometheus-blackbox-exporter = {
    environment.GOMEMLIMIT = "32MiB";
    # Keep headroom above the Go soft limit for non-Go allocations.
    serviceConfig = { MemoryHigh = "48M"; MemoryMax = "64M"; };
  };

  services.vmagent.prometheusConfig.scrape_configs = [
    {
      job_name = "pi-blackbox-exporter";
      static_configs = [ { targets = [ "127.0.0.1:9115" ]; } ];
    }
    {
      job_name = "pi-blackbox";
      scrape_interval = "60s";
      scrape_timeout = "10s";
      metrics_path = "/probe";
      static_configs = [
        { targets = [ "10.32.130.1:443" ]; labels = { probe = "gateway-admin"; module = "tcp_connect"; }; }
        { targets = [ "10.32.140.1:443" ]; labels = { probe = "gateway-services"; module = "tcp_connect"; }; }
        { targets = [ "https://auth.home.kelch.io/status" ]; labels = { probe = "kanidm"; module = "http_kanidm_status"; }; }
        { targets = [ "https://athena.home.kelch.io:5001/" ]; labels = { probe = "athena-dsm"; module = "http_2xx"; }; }
        { targets = [ "https://jellyfin.home.kelch.io/web/" ]; labels = { probe = "jellyfin"; module = "http_2xx"; }; }
        { targets = [ "https://grafana.home.kelch.io/" ]; labels = { probe = "grafana"; module = "http_redirect"; }; }
        { targets = [ "https://home.kelch.io/" ]; labels = { probe = "homepage"; module = "http_401"; }; }
        { targets = [ "https://echo.kelch.io/" ]; labels = { probe = "cloudflare-tunnel"; module = "http_2xx"; }; }
        { targets = [ "10.32.130.2:53" ]; labels = { probe = "k8s-gateway"; module = "dns_k8s_gateway"; }; }
        { targets = [ "10.32.1.1" ]; labels = { probe = "unifi-gateway"; module = "icmp"; }; }
      ];
      relabel_configs = [
        { source_labels = [ "__address__" ]; target_label = "__param_target"; }
        { source_labels = [ "module" ]; target_label = "__param_module"; }
        # VMAuth owns instance; retain the destination separately.
        { source_labels = [ "__param_target" ]; target_label = "target"; }
        { target_label = "__address__"; replacement = "127.0.0.1:9115"; }
      ];
    }
  ];
}
