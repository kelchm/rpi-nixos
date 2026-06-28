{ ... }:
{
  # Console + log debuggability profile

  services.getty.autologinUser = "kelchm";
  services.journald.extraConfig = "Storage=persistent";
}
