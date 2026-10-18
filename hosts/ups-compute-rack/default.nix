{ pkgs, ... }:
{
  imports = [
    ../../modules/hardware/pi5.nix
    ../../modules/roles/ups.nix
    ../../modules/profiles/metrics.nix
  ];

  # nvmd pins nixos-25.11; stateVersion matches.
  system.stateVersion = "25.11";

  # CyberPower UPS attached via USB. `usbhid-ups` is the generic HID Power
  # Device driver and works for the vast majority of modern USB UPSes
  # (APC, CyberPower, modern Liebert/Vertiv). If telemetry comes back wrong
  # or sparse, look at NUT's HCL and try a vendor-specific driver.
  power.ups.ups."compute-rack" = {
    driver = "usbhid-ups";
    port = "auto";
    description = "CyberPower UPS feeding the compute rack";
  };

  # upsmon watches this UPS via the local upsd. powerValue=1 satisfies NUT's
  # MINSUPPLIES requirement; auto-shutdown of the Pi itself isn't critical
  # since the Pi is small and the UPS battery should outlast it easily.
  # POC placeholder password — see TODO in modules/roles/ups.nix.
  power.ups.upsmon.monitor."compute-rack" = {
    system = "compute-rack@localhost";
    user = "monuser";
    passwordFile = "${pkgs.writeText "ups-poc-monuser-pw" "poc-placeholder"}";
    type = "primary";
    powerValue = 1;
  };
}
