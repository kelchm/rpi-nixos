{ ... }:
{
  users.mutableUsers = false;

  users.users.kelchm = {
    isNormalUser = true;
    extraGroups = [ "wheel" "audio" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPYJciC2PUIbONdO2YSwCko138IJXGP82jjHXy83oFt4"
    ];
  };

  # Passwordless sudo for the wheel group — fine for SSH-key-only access.
  security.sudo.wheelNeedsPassword = false;
}
