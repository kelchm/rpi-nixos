{ flakePath }:
let
  flake = builtins.getFlake flakePath;
  lock = builtins.fromJSON (builtins.readFile (flake.outPath + "/flake.lock"));
  inputs = lock.nodes.${lock.root}.inputs;
in
{
  # A routine refresh must keep both the OS channel and the Pi release fixed.
  nixosChannel = lock.nodes.${inputs.nixpkgs}.original;
  raspberryPi = lock.nodes.${inputs.nixos-raspberrypi}.locked;
  hosts = builtins.mapAttrs (_: host:
    let
      inherit (host) config pkgs;
      kernel = config.boot.kernelPackages.kernel;
      firmwareSources = builtins.concatLists host.options.hardware.firmware.definitions;
    in
    {
      kernel = kernel.drvPath;
      kernelModules = kernel.modules.outPath;
      deviceTrees = "${kernel}/dtbs";
      useGenerationDeviceTree = config.boot.loader.raspberry-pi.useGenerationDeviceTree;
      bootloader = config.boot.loader.raspberry-pi.bootloader;
      extraModules = map (package: package.drvPath) config.boot.extraModulePackages;
      gpuFirmware = config.boot.loader.raspberry-pi.firmwarePackage.drvPath;
      uboot = config.boot.loader.raspberry-pi.ubootPackage.drvPath;
      wirelessFirmware = pkgs.raspberrypiWirelessFirmware.drvPath;
      firstFirmwareSource = (builtins.head firmwareSources).drvPath;
    }
  ) flake.nixosConfigurations;
}
