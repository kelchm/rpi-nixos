{ nixos-raspberrypi, lib, ... }:
{
  # Pi 5 (bcm2712) via nvmd/nixos-raspberrypi — see project_upstream_strategy.md.
  # The archived nix-community/raspberry-pi-nix triggers a vc4-drm kernel hang
  # on Pi 5 with nixos-25.05+ (issue #123, bcm2712_iommu_of_xlate); nvmd is the
  # actively-maintained successor.
  imports = [
    # Hardware support: kernel, firmware, DTBs, bootloader.
    nixos-raspberrypi.nixosModules.raspberry-pi-5.base
    # HDMI display via vc4. Per nvmd README:
    #   display-vc4  → "regular" display connected (HDMI, what we use)
    #   display-rp1  → RP1-connected (DPI/composite/MIPI DSI panel — e.g. uConsole-like)
    # Keep enabled even on headless hosts so a monitor + cable can be hooked up for debug.
    nixos-raspberrypi.nixosModules.raspberry-pi-5.display-vc4
    # SD-image builder. Without this, no rootfs definition → eval fails.
    # Sets up FIRMWARE + NIXOS_SD partitions and the populate hooks.
    nixos-raspberrypi.nixosModules.sd-image
    # Skipping nixos-raspberrypi.nixosModules.raspberry-pi-5.page-size-16k:
    # the 16K page-size kernel breaks some userspace (jemalloc, certain Go
    # binaries). Default 4K is fine for our workloads.
  ];

  # Per nvmd README recommendation for new installations: use the new
  # generational bootloader ("kernel"), which supports multiple NixOS
  # generations. The base module defaults to "kernelboot" (legacy); override.
  boot.loader.raspberry-pi.bootloader = "kernel";

  # Wired ethernet via DHCP — Pi 5 sits in a rack on cabled LAN.
  networking = {
    useDHCP = false;
    interfaces.eth0.useDHCP = true;
  };

  # ZFS userspace from our nixos-26.05 nixpkgs would mismatch nvmd's kernel
  # (pinned to nixos-25.11) and trigger the "kernel module and userspace
  # tooling versions are not matching" assertion. We don't use ZFS — disable.
  boot.supportedFilesystems.zfs = lib.mkForce false;

  # Free up some boot space.
  documentation.enable = lib.mkDefault false;
  documentation.nixos.enable = lib.mkDefault false;

  # Serial console enabled so a USB-TTL cable on GPIO 6/8/10 gives us a
  # debuggable console even if HDMI/network are misbehaving. enable_uart is
  # already set by raspberry-pi-5.base; we just need the kernel params + getty.
  # tty1 (HDMI fb) listed first; ttyAMA0 last means /dev/console binds there
  # — early-boot kernel messages will appear on UART.
  boot.kernelParams = [
    "console=tty1"
    "console=ttyAMA0,115200n8"
  ];

  # NixOS does NOT auto-spawn a getty on a console= kernel arg — must be
  # explicit. Without this, the kernel writes to UART but no login prompt.
  systemd.services."serial-getty@ttyAMA0" = {
    enable = true;
    wantedBy = [ "getty.target" ];
    serviceConfig.Restart = "always";
  };
}
