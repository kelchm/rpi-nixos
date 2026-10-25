# Vendored from nixpkgs master (2aabd8a46fd9261d3cbbc5f95a53a33220aa56f2). shairport-sync 5.6 talks to nqptp
# over shared-memory interface smi11, which needs nqptp 1.2.9; nixos-26.05
# ships 1.2.8 (smi10). Keep in lockstep with ./shairport-sync.nix.
{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
  pkg-config,
  gitUpdater,
}:

stdenv.mkDerivation (finalAttrs: {
  version = "1.2.9";
  pname = "nqptp";

  src = fetchFromGitHub {
    owner = "mikebrady";
    repo = "nqptp";
    tag = finalAttrs.version;
    hash = "sha256-qqDqUFtqJjODxSX7eEE6DObXIE6X0LjxnneVlg6uJaw=";
  };

  nativeBuildInputs = [
    autoreconfHook
    pkg-config
  ];

  passthru.updateScript = gitUpdater {
    ignoredVersions = ".*(-dev|d0)";
  };

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
