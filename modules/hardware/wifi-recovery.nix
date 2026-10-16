{ pkgs, ... }:
let
  # Escalating self-heal for a wedged wlan0. wpa_supplicant already retries
  # forever on a plain disassociation, so this only matters when the layer
  # underneath it is stuck: on 2026-10-03 the streamer dropped off Wi-Fi and
  # stayed off for 13 days with the OS still running (weekly timer stamps
  # were written mid-outage), which points at the brcmfmac driver/firmware.
  #
  # One failed gateway ping per minute advances the ladder:
  #   3 → restart wpa_supplicant
  #   6 → reload brcmfmac (re-downloads the chip firmware; NixOS's udev rule
  #       restarts wpa_supplicant when wlan0 reappears)
  #  10 → reboot
  #
  # The journal is volatile (see common.nix), so before each step a short
  # snapshot of driver and supplicant state goes to /var/log/wifi-recovery.
  # That costs SD writes only when something is actually broken.
  wifiRecovery = pkgs.writeShellApplication {
    name = "wifi-recovery";
    runtimeInputs = with pkgs; [ coreutils findutils gawk iproute2 iputils iw kmod systemd wpa_supplicant ];
    text = ''
      state=/run/wifi-recovery/failures
      logdir=/var/log/wifi-recovery
      mkdir -p "''${state%/*}" "$logdir"

      gw=$(ip -4 route show default dev wlan0 | awk '{print $3; exit}')
      if [ -n "$gw" ] && ping -c 3 -W 2 -I wlan0 "$gw" >/dev/null 2>&1; then
        if [ -s "$state" ]; then
          echo "wlan0 recovered after $(cat "$state") failed checks"
          rm -f "$state"
        fi
        exit 0
      fi

      n=$(( $(cat "$state" 2>/dev/null || echo 0) + 1 ))
      echo "$n" > "$state"
      echo "gateway ''${gw:-(no default route)} unreachable, check $n"

      snapshot() {
        f="$logdir/$(date +%Y%m%dT%H%M%S)-$1.log"
        {
          iw dev wlan0 link
          ip addr show wlan0
          wpa_cli -i wlan0 status
          journalctl -b -k --since -30min --no-pager
          journalctl -b -u wpa_supplicant -u dhcpcd --since -30min --no-pager
        } > "$f" 2>&1 || true
        find "$logdir" -name '*.log' -printf '%T@ %p\n' | sort -rn | tail -n +21 | cut -d' ' -f2- | xargs -r rm -f
        sync
      }

      case $n in
        3) snapshot restart-supplicant; systemctl restart wpa_supplicant ;;
        6) snapshot reload-driver; modprobe -r brcmfmac_wcc brcmfmac; modprobe brcmfmac ;;
        10) snapshot reboot; systemctl reboot ;;
      esac
    '';
  };
in
{
  systemd.services.wifi-recovery = {
    description = "Recover a wedged wlan0";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${wifiRecovery}/bin/wifi-recovery";
    };
  };

  systemd.timers.wifi-recovery = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1min";
    };
  };
}
