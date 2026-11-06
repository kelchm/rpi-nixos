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
    # roamoff=1 (pi-zero-2w.nix) leaves roaming to wpa_supplicant, which
    # roams only with bgscan: without it the streamer stayed for a day on the
    # Office AP a floor up, and later on one it heard at -78 dBm with the
    # Basement AP at -53. brcmfmac can't report signal changes, so bgscan
    # sets its interval at association: every 30 s for about an hour below
    # -70 dBm, otherwise hourly. Each scan can roam to a better AP.
    templates."wpa_supplicant-network.conf" = {
      content = ''
        country=US
        ctrl_interface=/run/wpa_supplicant/control
        ctrl_interface_group=wpa_supplicant
        network={
          ssid="${config.sops.placeholder.wifi-ssid}"
          psk=${config.sops.placeholder.wifi-psk}
          bgscan="simple:30:-70:3600"
        }
      '';
      owner = "wpa_supplicant";
      mode = "0400";
      # A rotated PSK changes only this file, not the unit, so restart it here.
      restartUnits = [ "wpa_supplicant.service" ];
    };
  };
}
