{ ... }:
{
  imports = [
    ../../modules/hardware/pi3.nix
    ../../modules/roles/adsb.nix
    ../../modules/profiles/metrics.nix
  ];

  # First installed on 26.05; bump only on deliberate format-and-reinstall.
  system.stateVersion = "26.05";

  # Carried over from the PiAware SD image this replaces (rtlsdr-gain 42,
  # adaptive dynamic range off).
  services.dump1090-fa.extraArgs = [
    "--gain"
    "42"
  ];
}
