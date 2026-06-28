{ nixos-raspberrypi, lib, ... }:
{
  # Pi Zero 2 W (bcm2710A1) via nvmd/nixos-raspberrypi.
  #
  # We unified on nvmd for ALL Pi hosts (not just Pi 5) — see
  # memory/project_upstream_strategy.md. The alternative (stock nixpkgs
  # sd-image-aarch64 + mainline kernel for Pi Zero 2 W, nvmd for Pi 5) creates
  # ongoing pain from mixed nixpkgs versions in one flake: ZFS mismatch,
  # competing stateVersions, two lib.nixosSystem helpers, two Cachixes.
  # Unifying trades "lowest theoretical risk" (NixOS-project-backed mainline)
  # for "one source of truth + one operational model."
  imports = [
    nixos-raspberrypi.nixosModules.raspberry-pi-02.base
    # HDMI for debug. VC4 driver, fine on Pi 02's VideoCore IV.
    nixos-raspberrypi.nixosModules.raspberry-pi-02.display-vc4
    # SD-image builder. Without this, no rootfs definition → eval fails.
    nixos-raspberrypi.nixosModules.sd-image
  ];

  # Pi 02 has no Ethernet — WiFi only. Configured per-host (each WiFi PSK is a
  # per-host sops secret).

  # Free up some boot space.
  documentation.enable = lib.mkDefault false;
  documentation.nixos.enable = lib.mkDefault false;

  # ZFS userspace would mismatch nvmd's pinned-25.11 kernel (kernel module vs
  # tooling version assertion). We don't use ZFS — disable.
  boot.supportedFilesystems.zfs = lib.mkForce false;

  # Serial console enabled so a USB-TTL on GPIO 6/8/10 is debuggable. The
  # enable_uart config.txt setting is already on via raspberry-pi-02.base.
  boot.kernelParams = [
    "console=tty1"
    "console=ttyAMA0,115200n8"
  ];

  systemd.services."serial-getty@ttyAMA0" = {
    enable = true;
    wantedBy = [ "getty.target" ];
    serviceConfig.Restart = "always";
  };

  # ACT LED steady-on instead of the kernel default heartbeat (which looks
  # frantic and made the user question whether the Pi was healthy).
  systemd.tmpfiles.rules = [
    "w /sys/class/leds/ACT/trigger - - - - default-on"
    "w /sys/class/leds/ACT/brightness - - - - 1"
  ];

  # NOTE: previous stock-sd-image config blacklisted snd_bcm2835 (phantom
  # 3.5mm jack — Pi Zero 2 W has no physical jack) and hci_uart_bcm / btbcm
  # (Bluetooth init failures). With nvmd's vendor kernel these may not be
  # needed (different driver setup) — re-add if symptoms reappear after deploy.
}
