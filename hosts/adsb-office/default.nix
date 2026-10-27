{ ... }:
{
  imports = [
    ../../modules/hardware/pi3.nix
    ../../modules/roles/adsb.nix
    ../../modules/profiles/metrics.nix
    ../../modules/profiles/logs
  ];

  # First installed on 26.05; bump only on deliberate format-and-reinstall.
  system.stateVersion = "26.05";
}
