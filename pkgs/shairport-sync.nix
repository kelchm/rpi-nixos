# Vendored from nixpkgs master (fbd0c4475cd4d47f2b6e14974df7b4757a1a785f, NixOS/nixpkgs#574221),
# bumped from 5.6 to 5.6.1. nixos-26.05 ships 5.0.4, which predates the
# pre-auth AirPlay 2 fixes in 5.5/5.5.1. Drop once 26.05 (or the next
# release we're on) carries >= 5.6.
{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
  pkg-config,
  openssl,
  avahi,
  alsa-lib,
  libplist,
  glib,
  libdaemon,
  libsodium,
  libgcrypt,
  ffmpeg-headless,
  libuuid,
  unixtools,
  popt,
  libconfig,
  libpulseaudio,
  libjack2,
  libsndfile,
  libao,
  libsoundio,
  mosquitto,
  nix-update-script,
  pipewire,
  soxr,
  sndio,
  enableAvahi ? true,
  enableAirplay2 ? false,
  enableStdout ? true,
  enableAlsa ? true,
  enableSndio ? true,
  enablePulse ? true,
  enablePipe ? true,
  enablePipewire ? true,
  enableAo ? true,
  enableJack ? true,
  enableSoundio ? true,
  enableMetadata ? true,
  enableMpris ? stdenv.hostPlatform.isLinux,
  enableMqttClient ? true,
  enableDbus ? stdenv.hostPlatform.isLinux,
  enableSoxr ? true,
  enableConvolution ? true,
  enableLibdaemon ? false,
  enableTinySVCmDNS ? true,

  # Enabling session bus support disables system bus support
  enableSessionBus ? true,
}:

let
  inherit (lib) optional optionals;
in

stdenv.mkDerivation (finalAttrs: {
  pname = "shairport-sync";
  version = "5.6.1";

  src = fetchFromGitHub {
    repo = "shairport-sync";
    owner = "mikebrady";
    tag = finalAttrs.version;
    hash = "sha256-EvKrd5rj/82nlCk10YBK0jPj99BpXVT4Rhxei0DlSSQ=";
  };

  nativeBuildInputs = [
    autoreconfHook
    pkg-config
  ]
  ++ optionals enableAirplay2 [
    libplist.bin
    unixtools.xxd
  ];

  buildInputs = [
    openssl
    popt
    libconfig
    ffmpeg-headless
  ]
  ++ optional enableAvahi avahi
  ++ optional enableLibdaemon libdaemon
  ++ optional enableAlsa alsa-lib
  ++ optional enableSndio sndio
  ++ optional enableMqttClient mosquitto
  ++ optional enablePulse libpulseaudio
  ++ optional enablePipewire pipewire
  ++ optional enableAo libao
  ++ optional enableJack libjack2
  ++ optional enableSoundio libsoundio
  ++ optional enableSoxr soxr
  ++ optional enableConvolution libsndfile
  ++ optionals enableAirplay2 [
    libplist
    libsodium
    libgcrypt
    libuuid
  ]
  ++ optional (enableDbus || enableMpris) glib;

  # 5.x parses the diagnostics log_show_* settings but never applies them, so
  # every line keeps the time-since-last-message prefix. Still unfixed upstream
  # on development (e802689320); drop once a release applies them.
  patches = [ ./shairport-sync-log-options.patch ];

  postPatch = lib.optionalString enableSessionBus ''
    substituteInPlace dbus/dbus-service.c --replace-fail 'G_BUS_TYPE_SYSTEM' 'G_BUS_TYPE_SESSION'
    substituteInPlace dbus/mpris-service.c --replace-fail 'G_BUS_TYPE_SYSTEM' 'G_BUS_TYPE_SESSION'
  '';

  enableParallelBuilding = true;

  preConfigure = lib.optionalString (enableDbus || enableMpris) ''
    export PATH=${glib.dev}/bin:$PATH
  '';

  configureFlags = [
    "--without-configfiles"
    "--sysconfdir=/etc"
    "--with-ssl=openssl"
  ]
  ++ optional enableAvahi "--with-avahi"
  ++ optional enablePulse "--with-pulseaudio"
  ++ optional enablePipewire "--with-pipewire"
  ++ optional enableAlsa "--with-alsa"
  ++ optional enableSndio "--with-sndio"
  ++ optional enableAo "--with-ao"
  ++ optional enableJack "--with-jack"
  ++ optional enableSoundio "--with-soundio"
  ++ optional enableStdout "--with-stdout"
  ++ optional enablePipe "--with-pipe"
  ++ optional enableSoxr "--with-soxr"
  ++ optional enableConvolution "--with-convolution"
  ++ optional enableDbus "--with-dbus-interface"
  ++ optional enableMetadata "--with-metadata"
  ++ optional enableMpris "--with-mpris-interface"
  ++ optional enableMqttClient "--with-mqtt-client"
  ++ optional enableTinySVCmDNS "--with-tinysvcmdns"
  ++ optional enableLibdaemon "--with-libdaemon"
  ++ optional enableAirplay2 "--with-airplay-2";

  strictDeps = true;
  __structuredAttrs = true;

  passthru.updateScript = nix-update-script {
    # ignore -dev tagged releases
    extraArgs = [ "--version-regex=^([0-9\\.]+)$" ];
  };

  meta = {
    homepage = "https://github.com/mikebrady/shairport-sync";
    description = "Airtunes server and emulator with multi-room capabilities";
    license = lib.licenses.mit;
    mainProgram = "shairport-sync";
    maintainers = with lib.maintainers; [
      jordanisaacs
    ];
    platforms = lib.platforms.unix;
  };
})
