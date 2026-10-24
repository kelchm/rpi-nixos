{ nixos-raspberrypi, lib, ... }:
{
  # Pi 3 Model B (bcm2837) via nvmd/nixos-raspberrypi. nvmd's rpi3 and rpi02
  # kernels are the same derivation, so this shares the streamer's kernel.
  imports = [
    nixos-raspberrypi.nixosModules.raspberry-pi-3.base
    # SD-image builder. Without this, no rootfs definition → eval fails.
    nixos-raspberrypi.nixosModules.sd-image
  ];

  # Same SoC family as the Pi 02, which stops booting with this overlay on
  # nvmd v1.20260801.0 (nvmd/nixos-raspberrypi#254). Headless, so KMS buys
  # nothing; the HDMI console falls back to the firmware framebuffer.
  hardware.raspberry-pi.config.all.dt-overlays.vc4-kms-v3d.enable = false;

  # Wired Ethernet via DHCP using NixOS's default DHCP-on-every-interface. The
  # Pi 3's Ethernet is a USB NIC, so its predictable name isn't eth0, and
  # nothing configures wlan0.

  # Free up some boot space.
  documentation.enable = lib.mkDefault false;
  documentation.nixos.enable = lib.mkDefault false;

  # ZFS userspace can mismatch nvmd's vendor kernel (kernel module vs
  # tooling version assertion). We don't use ZFS — disable.
  boot.supportedFilesystems.zfs = lib.mkForce false;

  # No serial getty here, for the same reason as pi-zero-2w.nix: the PL011
  # belongs to Bluetooth, and systemd-getty-generator already skips consoles
  # that don't exist.
}
