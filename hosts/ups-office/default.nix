{ pkgs, ... }:
{
  imports = [
    ../../modules/hardware/pi5.nix
    ../../modules/roles/ups.nix
  ];

  # nvmd pins nixos-25.11; stateVersion matches.
  system.stateVersion = "25.11";

  # Vertiv Liebert PSA5 via USB (10af:0002, enumerates as "PowerSure PST").
  # Handled by usbhid-ups's Belkin/Liebert subdriver, but needs three
  # non-default driver options (diagnosed on-device, 2026-08; NUT issue #2271):
  #
  #   - The PSA5 is a composite USB device with TWO HID interfaces.
  #     Interface 0 is a 27-byte vendor stub (opaque ff000001.ff000002
  #     tunnel — zero UPS data); the real 816-byte HID power-device tree
  #     lives on interface 1, endpoint 0x82. NUT defaults to interface 0,
  #     yielding no telemetry and a bogus "OB" status. usb_hid_rep_index
  #     selects the interface; usb_hid_ep_in the matching IN endpoint.
  #   - The interrupt pipe on interface 1 periodically delivers a corrupt
  #     report: ACPresent=0 while Charging=1 (self-contradictory), which
  #     poisons NUT's report cache and flips status to OB on wall power.
  #     `pollonly` ignores the interrupt pipe entirely; clean GET_REPORT
  #     polls (every pollinterval, default 2s) were 100% consistent over
  #     a 90s soak. Cost: power-loss detection latency is ~2s instead of
  #     instant. Fine for monitoring.
  power.ups.ups."office" = {
    driver = "usbhid-ups";
    port = "auto";
    description = "Liebert PSA5 feeding the Starlink + T-Mobile gateways";
    directives = [
      "usb_hid_rep_index = 1"
      "usb_hid_ep_in = 2"
      "pollonly"
    ];
  };

  # upsmon watches this UPS via the local upsd. powerValue=1 satisfies NUT's
  # MINSUPPLIES requirement; auto-shutdown of the Pi itself isn't critical
  # since the Pi is small and the UPS battery should outlast it easily.
  # POC placeholder password — see TODO in modules/roles/ups.nix.
  power.ups.upsmon.monitor."office" = {
    system = "office@localhost";
    user = "monuser";
    passwordFile = "${pkgs.writeText "ups-poc-monuser-pw" "poc-placeholder"}";
    type = "primary";
    powerValue = 1;
  };
}
