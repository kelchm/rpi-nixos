# nixos-26.05's fluent-bit at 5.1.5, the release home-lab's host collectors pin.
# 5.0.7 parses the same config, but lacks two fixes the Pis' buffer relies on:
# a rejected OTLP batch no longer gets released by a later batch's success
# (5.1.3), and storage.total_limit_size eviction counts a chunk's real growth
# (5.0.8). Drop once the nixpkgs we're on ships >= 5.1.5.
{ fluent-bit, fetchFromGitHub }:

fluent-bit.overrideAttrs (finalAttrs: _: {
  version = "5.1.5";
  src = fetchFromGitHub {
    owner = "fluent";
    repo = "fluent-bit";
    tag = "v${finalAttrs.version}";
    hash = "sha256-L76MOMlT9xKGwtdnwtA1+lrLa50NnCqCvUdR12X1oao=";
  };
})
