{
  python3Packages,
  src,
  version,
}:

# The multilateration client piaware runs as fa-mlat-client. Keep its tag on
# the one FlightAware's piaware_builder pairs with our piaware. The source and
# version come from the flake's mlat-client input.
python3Packages.buildPythonApplication {
  pname = "mlat-client";
  inherit src version;
  pyproject = true;

  build-system = [ python3Packages.setuptools ];
  # asyncore left the standard library in Python 3.12; FlightAware's own
  # Trixie build uses the same backport.
  dependencies = [ python3Packages.pyasyncore ];
}
