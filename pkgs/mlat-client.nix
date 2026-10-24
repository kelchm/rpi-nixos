{
  python3Packages,
  fetchFromGitHub,
}:

# The multilateration client piaware runs as fa-mlat-client. Same tag as
# FlightAware's piaware_builder uses for piaware 11.1.
python3Packages.buildPythonApplication rec {
  pname = "mlat-client";
  version = "0.2.13";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "mutability";
    repo = "mlat-client";
    tag = "v${version}";
    hash = "sha256-fSjkEyE8oP9HQlZCAqCjvOchDyNpFqm8qlkMg373/kE=";
  };

  build-system = [ python3Packages.setuptools ];
  # asyncore left the standard library in Python 3.12; FlightAware's own
  # Trixie build uses the same backport.
  dependencies = [ python3Packages.pyasyncore ];
}
