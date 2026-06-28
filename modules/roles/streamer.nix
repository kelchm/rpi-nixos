{ config, pkgs, ... }:
{
  # ALSA diagnostics — only relevant for hosts that actually have audio hw.
  environment.systemPackages = with pkgs; [ alsa-utils ];

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    # System-wide mode: PipeWire runs as a system service (not per-user).
    # Required because shairport-sync is a system daemon with no user session.
    # State dir lives at /var/lib/pipewire/.local/state/wireplumber/.
    systemWide = true;
    alsa.enable = true;
    pulse.enable = true;

    # Volume architecture: every digital stage at unity, the speaker's analog
    # knob is the sole moving master. See README's audio architecture notes.
    #
    # Two layers were stealing ~47 dB on a fresh boot:
    #   - WirePlumber 0.5 ships device.routes.default-sink-volume = 0.4^3 = 0.064
    #     linear = -24 dB for every freshly-detected sink
    #   - PCM2704 on-chip 'PCM Playback Volume' defaults to ~64% = -23 dB
    #
    # Flat dotted-key form is REQUIRED for wireplumber.extraConfig — nesting
    # these as Nix sub-attrs silently emits the wrong SPA-JSON section header.
    wireplumber.extraConfig."10-streamer-volume" = {
      "wireplumber.settings"."device.routes.default-sink-volume" = 1.0;
      "wireplumber.settings"."device.routes.default-source-volume" = 1.0;
      "wireplumber.settings"."node.stream.default-playback-volume" = 1.0;
      # Headless receiver: don't remember per-app volumes across runs (would
      # resurrect any once-set lower stream volume from /var/lib/pipewire/).
      "wireplumber.settings"."node.stream.restore-props" = false;
    };

    # PCM2704 quirk: its on-chip 'PCM Playback Volume' is a digital attenuator
    # applied BEFORE the 16-bit Δ-Σ modulator — every dB of attenuation throws
    # away bit depth. Tell PipeWire to never write to that control; if any
    # attenuation is needed it stays in float upstream.
    #
    # Match by device.product.name (chip-stable) rather than device.name
    # (varies with USB vendor strings — this chip stores literally "Vendor
    # strings are placed here." in its USB descriptor by default).
    wireplumber.extraConfig."20-pcm2704-softvol" = {
      "monitor.alsa.rules" = [{
        matches = [{ "device.product.name" = "~PCM2704.*"; }];
        actions.update-props."api.alsa.soft-mixer" = true;
      }];
    };
  };

  # asound.state persistence: PipeWire stops writing to the hw mixer (above),
  # so the kernel keeps whatever amixer last stored. Without this, the mixer
  # resets to driver default (~64% / -23 dB) on every reboot and USB hot-replug.
  hardware.alsa.enablePersistence = true;

  # AirPlay 1 receiver. AP1 because AP2 attempt failed at the PTP-sync stage
  # — see project_airplay2_pending memory for details. Revisit when the Pi
  # can be put on the same L2 subnet as the AirPlay source devices.
  #
  # Volume policy: let the AirPlay sender's slider drive output via
  # shairport-sync's internal software attenuator. dasl_tapered maps the
  # AirPlay 30 dB range perceptually-linearly across the available headroom
  # (vs `standard` which is logarithmic but has audible jumps at the bottom).
  # Bit-perfect at slider-max; mildly lossy below. The right trade for a
  # desk-side speaker where the Mac slider is the day-to-day master.
  # PipeWire stays at unity (see wireplumber.extraConfig above); the D3V knob
  # is for setting absolute max output once and not touching.
  services.shairport-sync = {
    enable = true;
    openFirewall = true;
    settings.general = {
      output_backend = "pw";
      ignore_volume_control = "no";
      volume_control_profile = "dasl_tapered";
    };
  };

  # NixOS integration gap: services.shairport-sync + services.pipewire.systemWide
  # don't auto-wire each other. The system PipeWire socket
  # (/run/pipewire/pipewire-0) is srw-rw---- pipewire pipewire, so daemons that
  # want to use it must be in the pipewire group. Without this, shairport-sync's
  # PipeWire backend silently fails the connect (EACCES) and loops
  # "pw_processor not running" while every audio frame is dropped.
  users.users.shairport.extraGroups = [ "pipewire" ];

  # services.shairport-sync renders its config to /etc/shairport-sync.conf
  # (NOT into the systemd unit's ExecStart). When only the conf changes,
  # NixOS doesn't re-fingerprint the unit and the running daemon keeps the
  # old config in memory until manual restart. Restart on config-file change
  # so deploys are point-and-go.
  systemd.services.shairport-sync.restartTriggers = [
    config.environment.etc."shairport-sync.conf".source
  ];
}
