{ ... }:
{
  # Console + log debuggability profile

  # NB: this also autologins any SERIAL getty, not just the HDMI one.
  services.getty.autologinUser = "kelchm";

  # Persist the journal so `journalctl -b -1` can read the previous boot.
  # Overrides the fleet-wide volatile default in common.nix (which is mkDefault
  # for exactly this reason). Costs SD writes — drop this import when done.
  #
  # Previously this set `services.journald.extraConfig = "Storage=persistent"`,
  # which was a no-op: nixpkgs already defaults services.journald.storage to
  # "persistent", so moving it here in 08ef3e5 changed nothing. Setting the
  # typed option instead means it actually overrides something now.
  services.journald.storage = "persistent";
}
