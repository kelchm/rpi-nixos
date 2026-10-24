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
    # Passed to wpa_supplicant with -I via networking.wireless.extraConfigFiles.
    # Since 26.05 the daemon runs as the unprivileged wpa_supplicant user and
    # only reads /etc/wpa_supplicant/imperative.conf as its main config, so
    # this file must be owned by that user and carries the globals too.
    templates."wpa_supplicant-network.conf" = {
      content = ''
        country=US
        ctrl_interface=/run/wpa_supplicant/control
        ctrl_interface_group=wpa_supplicant
        network={
          ssid="${config.sops.placeholder.wifi-ssid}"
          psk=${config.sops.placeholder.wifi-psk}
        }
      '';
      owner = "wpa_supplicant";
      mode = "0400";
      # A rotated PSK changes only this file, not the unit, so restart it here.
      restartUnits = [ "wpa_supplicant.service" ];
    };
  };
}
