{
  tcl,
  tclPackages,
  fetchFromGitHub,
  autoreconfHook,
}:

# FlightAware's Tcl application launcher. A copy named `foo` in bin/ runs
# ../lib/foo/main.tcl; piaware installs itself that way.
tcl.mkTclDerivation rec {
  pname = "tcllauncher";
  version = "1.10";

  src = fetchFromGitHub {
    owner = "flightaware";
    repo = "tcllauncher";
    tag = "v${version}";
    hash = "sha256-BVrsoczKeBBoM1Q3v6EJY81QwsX6xbUqFkcBb482WH4=";
  };

  nativeBuildInputs = [ autoreconfHook ];
  propagatedBuildInputs = [ tclPackages.tclx ];

  # The bare binary refuses to run under its own name; piaware's install copies
  # it, so a TCLLIBPATH wrapper here would only be copied and then misnamed.
  dontWrapTclBinaries = true;
}
