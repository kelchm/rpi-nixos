{ config, ... }:
{
  sops = {
    defaultSopsFile = ../../secrets/streamer-basement-workbench.yaml;

    # Individual values land at /run/secrets/<name> (root:root 0400).
    secrets.wifi-ssid = { };
    secrets.wifi-psk = { };

    # Render the wpa_supplicant network={} block from the two secrets above.
    # Both SSID and PSK live only in the sops payload; nothing about the WiFi
    # network appears in the Nix store, the flake source, or git history.
    # Spliced into wpa_supplicant.conf via networking.wireless.extraConfigFiles.
    templates."wpa_supplicant-network.conf" = {
      content = ''
        network={
          ssid="${config.sops.placeholder.wifi-ssid}"
          psk=${config.sops.placeholder.wifi-psk}
        }
      '';
      mode = "0400";
    };
  };
}
