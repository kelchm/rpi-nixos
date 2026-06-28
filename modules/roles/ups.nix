{ pkgs, ... }:
{
  # NUT (Network UPS Tools) server. Per-host config declares the specific UPS
  # under `power.ups.ups.<name>` and the upsmon monitor entry pointing at it.
  #
  # Scope: standalone mode, listens on the LAN so other hosts can query
  # telemetry (reads are anonymous in NUT — no auth needed for upsc).
  # The monuser password is a placeholder; it only matters when we add
  # secondary upsmon hosts for coordinated shutdown, at which point migrate
  # to sops-nix.
  power.ups = {
    enable = true;
    mode = "standalone";
    upsd.listen = [
      { address = "0.0.0.0"; port = 3493; }
      { address = "::"; port = 3493; }
    ];

    # NUT requires upsmon, and upsmon requires a user to log in to upsd as.
    # Placeholder password — only consequential once we add upsmon secondaries
    # or expose this to less-trusted networks. TODO: sops-manage when either.
    users."monuser" = {
      passwordFile = "${pkgs.writeText "ups-poc-monuser-pw" "poc-placeholder"}";
      upsmon = "primary";
    };
  };

  networking.firewall.allowedTCPPorts = [ 3493 ];

  environment.systemPackages = with pkgs; [ nut ];
}
