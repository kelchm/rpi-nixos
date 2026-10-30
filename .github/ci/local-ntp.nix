{ hosts }:
let
  pkgs = (builtins.head hosts).pkgs;
  configFile = host:
    let
      command = host.config.systemd.services.chronyd.serviceConfig.ExecStart;
      path = builtins.head (builtins.match ".* -f ([^ ]+).*" command);
    # match drops string context; retain the generated config as a build input.
    in pkgs.lib.strings.addContextFrom command path;
in
pkgs.runCommand "check-local-ntp-config" {
  nativeBuildInputs = [ pkgs.chrony ];
} ''
  mkdir "$out"
  ${pkgs.lib.concatMapStringsSep "\n" (host: ''
    # Parse the actual rendered daemon configuration without starting a
    # daemon, contacting an upstream, or changing the builder's clock.
    chronyd -p -f ${configFile host} > "$out/${host.config.networking.hostName}.conf"
  '') hosts}
''
