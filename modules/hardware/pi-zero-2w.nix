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
    ./wifi-recovery.nix
  ];

  # Pi 02 has no Ethernet — WiFi only. Configured per-host (each WiFi PSK is a
  # per-host sops secret).

  # brcmfmac options Raspberry Pi OS ships by default (rpi-brcmfmac.conf in
  # firmware-nonfree) and nvmd does not. roamoff=1 hands roaming decisions to
  # wpa_supplicant instead of the chip firmware; our BCM43430/2 firmware
  # (9.88.4.77) has an open report of wedging after switching APs and never
  # reconnecting (RPi-Distro/firmware-nonfree#27). feature_disable clears
  # FWSUP | SAE | DUMP_OBSS — bit positions shift between kernels (see
  # raspberrypi/linux#7634), so re-derive this mask from feature.h on any
  # kernel bump rather than copying RPi OS's current value.
  boot.extraModprobeConfig = ''
    options brcmfmac roamoff=1 feature_disable=0x282000
  '';

  # Free up some boot space.
  documentation.enable = lib.mkDefault false;
  documentation.nixos.enable = lib.mkDefault false;

  # ZFS userspace would mismatch nvmd's pinned-25.11 kernel (kernel module vs
  # tooling version assertion). We don't use ZFS — disable.
  boot.supportedFilesystems.zfs = lib.mkForce false;

  # No explicit serial-console wiring here — deliberately. raspberry-pi-02.base
  # already emits `console=serial0,115200n8 console=tty1` and sets enable_uart=1,
  # and systemd-getty-generator spawns a serial getty for the consoles that
  # actually exist (skipping the ones that don't).
  #
  # We previously hard-coded `systemd.services."serial-getty@ttyAMA0"` with
  # Restart="always". Declaring a concrete instance SHADOWS systemd's
  # serial-getty@.service template and so discards its BindsTo=dev-%i.device
  # guard — the one thing preventing a getty from being started against an
  # absent device. On Pi Zero 2 W the PL011 is owned by the Bluetooth serdev, so
  # /dev/ttyAMA0 never appears: the unit restart-looped indefinitely (1,889
  # restarts in 23 h of uptime), and the resulting journald churn was the
  # dominant source of SD-card writes on this host.
  #
  # If a serial console is ever wanted here, free the PL011 with a disable-bt
  # overlay — do not force a getty at a device that isn't there.

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
