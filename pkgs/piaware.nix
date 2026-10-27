{
  lib,
  tcl,
  tclPackages,
  src,
  version,
  openssl,
  coreutils,
  iproute2,
  nettools,
  tcllauncher,
  mlat-client,
  dump1090-fa,
}:

# FlightAware's ADS-B uploader. Not in nixpkgs. Built the way upstream's
# piaware_builder does, with tcllauncher copied in as each program's binary.
# The source and version come from the flake's piaware input.
tcl.mkTclDerivation {
  pname = "piaware";
  inherit src version;

  # c_rehash for the bundled CA certificates.
  nativeBuildInputs = [ openssl ];
  # tcllauncher's binary loads its own Tcl package, so it goes on TCLLIBPATH too.
  propagatedBuildInputs = with tclPackages; [
    tcllauncher
    tcllib
    tcltls
    tclx
    incrtcl
  ];

  # Helpers live in this package rather than /usr/lib/piaware, and system
  # tools come from the wrapper's PATH.
  postPatch = ''
    substituteInPlace programs/piaware/{faup1090,faup978,mlat}.tcl \
      --replace-fail /usr/lib/piaware/helpers/ $out/lib/piaware/helpers/
    substituteInPlace package/fa_sysinfo.tcl \
      --replace-fail /bin/df df \
      --replace-fail /sbin/ip ip
    substituteInPlace programs/piaware/{helpers,login}.tcl \
      --replace-fail /bin/uname uname
    substituteInPlace programs/piaware/update.tcl \
      --replace-fail /sbin/reboot reboot \
      --replace-fail /sbin/halt halt
  '';

  dontConfigure = true;
  dontBuild = true;

  makeFlags = [
    "DESTDIR=$(out)"
    "PREFIX="
    "TCLLAUNCHER=${tcllauncher}/bin/tcllauncher"
    "TCLSH=${tcl}/bin/tclsh"
  ];

  postInstall = ''
    ln -s ${dump1090-fa}/bin/faup1090 $out/lib/piaware/helpers/faup1090
    ln -s ${mlat-client}/bin/fa-mlat-client $out/lib/piaware/helpers/fa-mlat-client
  '';

  # tcllauncher finds main.tcl from its own name, so the wrapper must pass it
  # through. netstat lets piaware see which program serves port 30005.
  tclWrapperArgs = [
    "--inherit-argv0"
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath [
      coreutils
      iproute2
      nettools
    ])
  ];

  meta = {
    description = "FlightAware ADS-B uploader";
    homepage = "https://github.com/flightaware/piaware";
    license = lib.licenses.bsd3;
    mainProgram = "piaware";
    platforms = lib.platforms.linux;
  };
}
