# Vendored from nixpkgs master (2aabd8a46fd9261d3cbbc5f95a53a33220aa56f2). The
# source and version come from the flake's nqptp input. shairport-sync 5.6
# talks to nqptp over shared-memory interface smi11, which needs nqptp 1.2.9;
# nixos-26.05 ships 1.2.8 (smi10). The streamer role checks that the two
# sources agree.
{
  lib,
  stdenv,
  src,
  version,
  autoreconfHook,
  pkg-config,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "nqptp";
  inherit src version;

  nativeBuildInputs = [
    autoreconfHook
    pkg-config
  ];

  postInstall = ''
    mkdir -p $out/lib/systemd/system
    cp nqptp.service $out/lib/systemd/system
  '';

  meta = {
    homepage = "https://github.com/mikebrady/nqptp";
    description = "Daemon and companion application to Shairport Sync that monitors timing data from any PTP clocks";
    license = lib.licenses.gpl2Only;
    mainProgram = "nqptp";
    maintainers = with lib.maintainers; [
      jordanisaacs
      adamcstephens
    ];
    platforms = lib.platforms.linux ++ lib.platforms.freebsd;
  };
})
