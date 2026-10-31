{ config, ... }:
{
  imports = [
    ../../modules/hardware/pi3.nix
    ../../modules/roles/adsb.nix
    ../../modules/profiles/metrics.nix
    ../../modules/profiles/logs
  ];

  # The two UPS Pis first, then the pool that served this host before them.
  # timesyncd takes only networkd's DHCP servers, not dhcpcd's, so this repeats
  # option 42 by hand. It ignores FallbackNTP while NTP is set, hence the pool.
  services.timesyncd.servers = [ "10.32.20.111" "10.32.20.112" ] ++ config.networking.timeServers;

  # First installed on 26.05; bump only on deliberate format-and-reinstall.
  system.stateVersion = "26.05";
}
