{ pkgs, ... }:
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

  # Debug-friendly defaults so we're not flying blind on HDMI when sshd is
  # unreachable. Cost is small; benefit is being able to actually diagnose.
  #   - autologin on tty1 → can scroll back + run journalctl at the console
  #   - persistent journal → `journalctl -b -1` reads the PREVIOUS boot
  # (kernel console=tty1 is already set by each hardware module.)
  services.getty.autologinUser = "kelchm";
  services.journald.extraConfig = "Storage=persistent";

  # stateVersion is per-host (set in each host's default.nix). All current
  # hosts build against nvmd's pinned nixpkgs (25.11), so they're uniformly
  # "25.11" today; keeping it per-host keeps a future split (one host bumping
  # ahead of another) cheap.
}
