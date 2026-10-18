{ config, ... }:
{
  imports = [
    ../../modules/hardware/pi-zero-2w.nix
    ../../modules/roles/streamer.nix
    ../../modules/profiles/metrics.nix
    ./secrets.nix
  ];

  # NixOS release this host was originally installed against. Matches the
  # version nvmd pins; bump only on deliberate format-and-reinstall.
  system.stateVersion = "25.11";

  # User-facing name in iOS/macOS AirPlay pickers.
  services.shairport-sync.settings.general.name = "Basement Workbench Speakers";

  # Thread border routers on Main and Guest announce the same on-link IPv6
  # prefix. Reflected Bonjour records then send Main clients looking for this
  # Pi on their own VLAN. Publish only its reachable IPv4 address until IPv6
  # routing between these networks is deliberately configured.
  services.avahi = {
    ipv6 = false;
    # Disabling IPv6 sockets alone still permits AAAA records over IPv4.
    extraConfig = ''
      [publish]
      publish-aaaa-on-ipv4=no
    '';
  };

  # WiFi: both SSID and PSK live in sops (see secrets.nix). The rendered
  # network={} block gets spliced into wpa_supplicant.conf at activation.
  # wpa_supplicant doesn't support ext: substitution for SSIDs, hence the
  # template+include approach rather than the simpler networks.<name>.pskRaw.
  networking.wireless = {
    enable = true;
    extraConfigFiles = [
      config.sops.templates."wpa_supplicant-network.conf".path
    ];
  };

  # NixOS's networking.wireless module only generates /etc/wpa_supplicant.conf
  # when `networks.<name>` is non-empty. We use extraConfigFiles instead (so
  # SSID stays in sops), so we provide the base config ourselves — just the
  # ctrl_interface + update_config bits wpa_supplicant needs before reading
  # the -I include files. The network={} block is in the sops-rendered include.
  environment.etc."wpa_supplicant.conf".text = ''
    ctrl_interface=DIR=/run/wpa_supplicant GROUP=wheel
    update_config=1
    country=US
  '';

  # Make wpa_supplicant wait for sops to render the included network={} block.
  # Without this, supplicant fires at boot before the include file exists,
  # fails reading it, stays in failed state, and only a manual restart picks
  # it up after sops finishes. Unit is `wpa_supplicant.service` (singular —
  # not `wpa_supplicant-wlan0` despite the per-interface flag in the script).
  systemd.services.wpa_supplicant = {
    after = [ "sops-install-secrets.service" ];
    wants = [ "sops-install-secrets.service" ];
  };
}
