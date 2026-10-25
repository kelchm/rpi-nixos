{ host }:
let
  inherit (host) pkgs;
  source = pkgs.raspberrypiWirelessFirmware;
  merged = host.config.hardware.firmware;
in
pkgs.runCommand "check-pi-wireless-firmware" {
  nativeBuildInputs = [ pkgs.zstd pkgs.xz ];
} ''
  set -euo pipefail
  # Check actual contents after firmware merging and compression, including
  # symlink aliases and board-specific NVRAM files, rather than package names.
  count=0
  while IFS= read -r -d "" file; do
    relative="''${file#${source}/lib/firmware/}"
    target="${merged}/lib/firmware/$relative"
    if [ -f "$target" ]; then
      cmp "$file" "$target"
    elif [ -f "$target.zst" ]; then
      zstd -dc "$target.zst" | cmp "$file" -
    elif [ -f "$target.xz" ]; then
      xz -dc "$target.xz" | cmp "$file" -
    else
      echo "Missing firmware: $relative" >&2
      exit 1
    fi
    count=$((count + 1))
  done < <(find -L ${source}/lib/firmware -type f -print0)
  test "$count" -gt 0
  echo "Verified $count Raspberry Pi firmware files in the merged tree"
  touch "$out"
''
