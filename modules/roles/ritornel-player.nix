{ config, lib, pkgs, sources, rust-overlay, ... }:
let
  rustToolchain = (rust-overlay.lib.mkRustBin { } pkgs).fromRustupToolchainFile
    "${sources.ritornel.src}/rust-toolchain.toml";
  ritornel = pkgs.callPackage ../../pkgs/ritornel.nix {
    inherit rustToolchain;
    inherit (sources.ritornel) src version rev tag;
  };

  dataDir = "/var/lib/ritornel";

  # The data directory is the service user's alone (0700), and a client
  # proves itself by reading server.json there. So `ritornelctl` on the host
  # runs the client as that user, against that directory.
  ritornelctl = pkgs.writeShellScriptBin "ritornelctl" ''
    if [ "$(${pkgs.coreutils}/bin/id -un)" != ritornel ]; then
      exec /run/wrappers/bin/sudo -u ritornel -- "$0" "$@"
    fi
    export RITORNEL_DATA_DIR=${dataDir}
    exec ${lib.getExe ritornel.ctl} "$@"
  '';
in
{
  # A Ritornel satellite: plays the hub's library through this host's
  # speakers and sends its listens to the hub. Sound goes through ALSA's
  # `default` device into the streamer role's system PipeWire. Joining the
  # hub is a one-time step per data directory; see docs/ritornel.md.

  environment.systemPackages = [ ritornelctl ];

  # The hub is reached by its .local name. common.nix enables both already;
  # a satellite depends on them, so say so here too.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };

  users.users.ritornel = {
    isSystemUser = true;
    group = "ritornel";
    home = dataDir;
    # The system PipeWire socket is pipewire:pipewire 0660, as for
    # shairport-sync (modules/roles/streamer.nix).
    extraGroups = [ "pipewire" ];
  };
  users.groups.ritornel = { };

  systemd.services.ritornel = {
    description = "Ritornel player";
    wantedBy = [ "multi-user.target" ];
    # No network-online.target: the server starts without its hub and finds
    # it again on its own.
    wants = [ "pipewire.service" "wireplumber.service" ];
    after = [ "pipewire.service" "wireplumber.service" ];
    environment = {
      RITORNEL_DATA_DIR = dataDir;
      # The ALSA PipeWire plugin looks for the socket here; the service has
      # no session and so no XDG_RUNTIME_DIR.
      PIPEWIRE_RUNTIME_DIR = "/run/pipewire";
      # Hub and clients list this player by the name its AirPlay receiver
      # has, not the hostname. A setting wins over the stored name each start.
      RITORNEL_NAME = config.services.shairport-sync.settings.general.name;
      # Masters pulled from the hub, kept on the SD card. 1 GiB holds a few
      # albums of CD rips; the default, 2 GiB, buys little but card wear.
      RITORNEL_CACHE_SIZE = "1 GiB";
    };
    serviceConfig = {
      User = "ritornel";
      Group = "ritornel";
      # No --listen: the server stays on loopback and opens no port.
      ExecStart = "${lib.getExe ritornel.server} serve --data-dir ${dataDir} --output default";
      StateDirectory = "ritornel";
      StateDirectoryMode = "0700";
      Restart = "on-failure";
      RestartSec = 10;

      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };
}
