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

  # Prefer these files over overlapping generic firmware. mkBefore makes hiPrio
  # stick: buildEnv keeps the first entry's priority when all-firmware.nix lists
  # the same package. CI checks the contents of the resulting tree.
  hardware.firmware = lib.mkBefore [ (lib.hiPrio wirelessFirmware) ];
}
