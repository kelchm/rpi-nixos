{ config, lib, pkgs, ... }:
{
  # Per-host dedicated age key for sops-nix. NOT the SSH host key (which
  # rotates on every reflash and creates a chicken-and-egg bootstrap problem
  # for WiFi-only hosts). See README's "Add or reflash a host" section.
  sops.age = {
    keyFile = "/var/lib/sops-nix/host-key.txt";
    generateKey = false;
  };

  # Force sops-nix to use a real systemd unit (sops-install-secrets.service)
  # instead of an activation script snippet. This gives us a concrete unit
  # we can order our key-install service against. Defaults to off on stock
  # NixOS (only auto-enables when sysusers/userborn is in use).
  sops.useSystemdActivation = true;

  # The host's age private key is dropped on /boot/firmware/sops-host-key by
  # the operator on the Mac before first boot. This one-shot service moves
  # it to the canonical sops-nix path with correct ownership, then removes
  # the FIRMWARE copy. Idempotent — ConditionPathExists negation makes it a
  # no-op on subsequent boots.
  #
  # /boot/firmware is x-systemd.automount on the rpi sd-image — NOT included
  # in local-fs.target. RequiresMountsFor triggers the automount and pins it
  # for the duration of our service so the stat in the script actually sees
  # the file.
  systemd.services.sops-host-key-install = {
    description = "Install per-host age key from FIRMWARE partition (one-shot)";
    wantedBy = [ "sops-install-secrets.service" ];
    before = [ "sops-install-secrets.service" ];
    unitConfig = {
      ConditionPathExists = "!/var/lib/sops-nix/host-key.txt";
      RequiresMountsFor = "/boot/firmware";
      DefaultDependencies = "no";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      src=/boot/firmware/sops-host-key
      if [ -f "$src" ]; then
        install -D -m 0600 -o root -g root "$src" /var/lib/sops-nix/host-key.txt
        rm -f "$src"
        echo "installed host age key from $src"
      else
        echo "no host age key found at $src; sops will fail if secrets are defined" >&2
      fi
    '';
  };
}
