{ lib, pkgs, nixos-raspberrypi, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  platform = nixos-raspberrypi.legacyPackages.${system};
  wirelessFirmware = nixos-raspberrypi.packages.${system}.raspberrypiWirelessFirmware;
in
{
  # Board modules already select kernels and GPU firmware from nvmd's own
  # package outputs. Keep U-Boot and Wi-Fi firmware in the same platform set.
  boot.loader.raspberry-pi.ubootPackage = lib.mkDefault platform.ubootRaspberryPi_64bit;
  nixpkgs.overlays = [ (_: _: { raspberrypiWirelessFirmware = wirelessFirmware; }) ];

  # linux-firmware can contain overlapping Broadcom files. The first package
  # wins, so pinning the package alone is insufficient: give it precedence.
  hardware.firmware = lib.mkBefore [ wirelessFirmware ];
}
