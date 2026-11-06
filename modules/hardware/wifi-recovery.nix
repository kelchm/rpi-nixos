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
  # and starts over (13, 16, 20, ...) if the reboot didn't happen.
  #
  # A firmware PSM watchdog reloads the driver straight away. It can leave
  # wlan0 associated but losing most frames: on 2026-11-05 the streamer's AP
  # retried ten times as often as usual and about one check in four failed,
  # so the count kept resetting and the ladder never got past check 2.
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

      snapshot() {
        f="$logdir/$(date +%Y%m%dT%H%M%S)-$1.log"
        {
          iw dev wlan0 link
          ip addr show wlan0
          # The hardened daemon only sees /run/wpa_supplicant, so wpa_cli's
          # reply socket must live there; NixOS creates this dir only for
          # userControlled setups.
          mkdir -p /run/wpa_supplicant/client
          wpa_cli -p /run/wpa_supplicant/control -i wlan0 status
          journalctl -b -k --since -30min --no-pager
          journalctl -b -u wpa_supplicant -u dhcpcd --since -30min --no-pager
        } > "$f" 2>&1 || true
        find "$logdir" -name '*.log' -printf '%T@ %p\n' | sort -rn | tail -n +21 | cut -d' ' -f2- | xargs -r rm -f
        sync
      }

      # The chip's vendor module (brcmfmac_cyw on the Zero 2 W) holds
      # brcmfmac, so remove its holders first; brcmfmac loads them again.
      reload_driver() {
        mapfile -t holders < <(find /sys/module/brcmfmac/holders -mindepth 1 -printf '%f\n' 2>/dev/null)
        modprobe -r "''${holders[@]}" brcmfmac || true
        modprobe brcmfmac
      }

      # The cursor lives in /run, so the first run after a boot reads the whole boot.
      fired=$(journalctl -b -k --cursor-file="''${state%/*}/kernel-cursor" --grep "PSM's watchdog has fired" -o cat --no-pager || true)
      if [ -n "$fired" ]; then
        echo "brcmfmac firmware watchdog fired, reloading the driver"
        snapshot psm-watchdog
        reload_driver
        exit 0
      fi

      # A missing wlan0 (driver never probed) must count as a failure too.
      gw=$(ip -4 route show default dev wlan0 2>/dev/null | awk '{print $3; exit}') || gw=""
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

      case $(( (n - 1) % 10 + 1 )) in
        3) snapshot restart-supplicant; systemctl restart wpa_supplicant ;;
        6) snapshot reload-driver; reload_driver ;;
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
