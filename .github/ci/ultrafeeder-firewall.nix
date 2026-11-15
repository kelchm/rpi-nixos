{ host }:
let
  inherit (host) config pkgs;
  inherit (pkgs) lib;
  service = config.systemd.services.podman-ultrafeeder;
  # Use the actual generated lifecycle scripts, as the NTP check does for
  # chrony's rendered configuration. No radio, container, or secrets are used.
  install = service.preStart;
  remove = lib.last (lib.splitString "\n" service.postStop);
  reload = lib.removePrefix "@" (builtins.head (lib.splitString " "
    config.systemd.services.firewall.serviceConfig.ExecReload));
in
pkgs.runCommand "ultrafeeder-firewall-test-tools" { } ''
  mkdir "$out"
  ln -s ${install} "$out/install"
  ln -s ${remove} "$out/remove"
  ln -s ${reload} "$out/reload"
  ln -s ${lib.getExe' config.networking.firewall.package "iptables"} "$out/iptables"
''
