{ lib, pkgs, ... }:
{
  imports = [ ./sops-host-key.nix ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    # Let the Mac (or any non-root admin) push closures to the nix-daemon over
    # SSH without signature checks. Marginal trust delta vs passwordless wheel.
    trusted-users = [ "root" "kelchm" ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # 512 MB RAM on Pi Zero 2 W → zram-backed swap; tmpfs /tmp to save SD writes.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
  boot.tmp.useTmpfs = true;

  # Journal to RAM, not the SD card. Every host here boots off microSD, and
  # journald measured as ~71% of ALL block writes on streamer-basement-workbench
  # (3.2 GB/day of a 4.4 GB/day total) — by far the largest wear source. Note
  # that retained journal size is NOT the same quantity: only ~52 MB was ever
  # held on disk, so a SystemMaxUse cap would have bounded nothing that mattered.
  #
  # Durable log history is the central log server's job (home-lab k8s), not this
  # SD card's. Until that ships, `journalctl -b -1` is unavailable — import
  # modules/profiles/debug.nix on a host to get persistence back while
  # investigating. mkDefault so that profile can override it.
  services.journald.storage = lib.mkDefault "volatile";
  services.journald.extraConfig = ''
    RuntimeMaxUse=16M
  '';

  # mDNS: publish our own services AND resolve other .local hosts.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tmux
  ];

  # stateVersion is per-host (set in each host's default.nix): the NixOS release
  # the host was first installed with. All current hosts were installed on 25.11,
  # so they stay "25.11" across nvmd release bumps; bump only on reinstall.
}
