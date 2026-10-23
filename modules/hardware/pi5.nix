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

  # ZFS userspace can mismatch nvmd's vendor kernel and trigger the "kernel
  # module and userspace tooling versions are not matching" assertion. We don't use ZFS — disable.
  boot.supportedFilesystems.zfs = lib.mkForce false;

  # Free up some boot space.
  documentation.enable = lib.mkDefault false;
  documentation.nixos.enable = lib.mkDefault false;

  # Serial console on the Pi 5's GPIO UART. /dev/ttyAMA0 genuinely exists here
  # (unlike Pi Zero 2 W, where PL011 belongs to the Bluetooth serdev), and
  # ups-compute-rack confirms it works: /sys/class/tty/console/active is
  # "tty1 ttyAMA0" with a live getty.
  #
  # Named explicitly rather than relying on the base's `console=serial0,...`:
  # serial0 is a device-tree ALIAS, and it is not established that Linux
  # resolves it from the extlinux append line the way the Pi firmware resolves
  # it in cmdline.txt. The working console today comes from this explicit
  # ttyAMA0 param, so it stays until proven redundant. Cheap insurance for the
  # one situation a serial console exists for — the network being down.
  boot.kernelParams = [
    "console=tty1"
    "console=ttyAMA0,115200n8"
  ];

  # NO explicit `systemd.services."serial-getty@ttyAMA0"` here — that was the
  # bug. Declaring a concrete instance SHADOWS systemd's serial-getty@.service
  # template and discards its BindsTo=dev-%i.device guard, which is what stops a
  # getty being started against a device that isn't present. It was harmless on
  # Pi 5 (the device exists) but the identical block on Pi Zero 2 W restart-
  # looped 1,889 times in 23 h and hammered the SD card via journald.
  # systemd-getty-generator creates the getty from console= on its own.
}
