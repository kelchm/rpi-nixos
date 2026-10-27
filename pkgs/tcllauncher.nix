{
  tcl,
  tclPackages,
  src,
  version,
  autoreconfHook,
}:

# FlightAware's Tcl application launcher. A copy named `foo` in bin/ runs
# ../lib/foo/main.tcl; piaware installs itself that way. The source and
# version come from the flake's tcllauncher input.
tcl.mkTclDerivation {
  pname = "tcllauncher";
  inherit src version;

  nativeBuildInputs = [ autoreconfHook ];
  propagatedBuildInputs = [ tclPackages.tclx ];

  # The bare binary refuses to run under its own name; piaware's install copies
  # it, so a TCLLIBPATH wrapper here would only be copied and then misnamed.
  dontWrapTclBinaries = true;
}
