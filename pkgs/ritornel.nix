# Ritornel's server and command-line client, from one pinned source.
#
# Two builds, because the feature flags belong to the server alone: the
# player is the server with its audio output (ALSA) and without Last.fm or a
# media session. Rust comes from the source's own rust-toolchain.toml.
{ lib, makeRustPlatform, rustToolchain, pkg-config, alsa-lib, src, version, rev, tag ? null }:
let
  rustPlatform = makeRustPlatform { cargo = rustToolchain; rustc = rustToolchain; };
  cargoDeps = rustPlatform.importCargoLock { lockFile = "${src}/Cargo.lock"; };
  build = { pname, cargoFlags, extra ? { } }: rustPlatform.buildRustPackage (lib.recursiveUpdate {
    inherit pname version src cargoDeps;
    cargoBuildFlags = [ "--package" pname ] ++ cargoFlags;
    # Ritornel's build script reads these when .git is absent in the Nix sandbox.
    env = {
      RITORNEL_BUILD_COMMIT = rev;
    } // lib.optionalAttrs (tag != null) {
      RITORNEL_BUILD_TAG = tag;
    };
    # Ritornel's CI runs the tests; here they would only slow the builder.
    doCheck = false;
    meta = {
      homepage = "https://github.com/ritornel/ritornel";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
      mainProgram = pname;
    };
  } extra);
in
{
  server = build {
    pname = "ritornel-server";
    cargoFlags = [ "--no-default-features" "--features" "audio-output" ];
    extra = {
      nativeBuildInputs = [ pkg-config ];
      buildInputs = [ alsa-lib ];
    };
  };
  ctl = build {
    pname = "ritornelctl";
    cargoFlags = [ ];
  };
}
