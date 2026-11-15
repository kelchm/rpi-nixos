#!/usr/bin/env bash
# Run only inside an isolated network namespace, with root and a 30s timeout.
set -euo pipefail
if test "$(readlink /proc/self/ns/net)" = "$(readlink /proc/1/ns/net)"; then
  echo 'Refusing to run in the host network namespace; use sudo timeout 30 unshare --net bash' >&2
  exit 2
fi
install=$1
remove=$2
reload=$3
# Use the same iptables implementation as the generated NixOS rules.
export PATH="$(dirname "$install"):$PATH"
client_pid=
server_pid=
trap 'test -z "$client_pid" || kill "$client_pid" 2>/dev/null || true; test -z "$server_pid" || kill "$server_pid" 2>/dev/null || true; wait || true' EXIT

unshare --net sleep 60 & client_pid=$!
unshare --net sleep 60 & server_pid=$!
for attempt in $(seq 1 30); do
  if test "$(readlink /proc/$client_pid/ns/net)" != "$(readlink /proc/$$/ns/net)" &&
     test "$(readlink /proc/$server_pid/ns/net)" != "$(readlink /proc/$$/ns/net)"; then break; fi
  sleep 0.02
done
ip link set lo up
ip link add lan0 type veth peer name lan1
ip link set lan1 netns "$client_pid"
ip addr add 10.223.0.1/24 dev lan0
ip link set lan0 up
nsenter -t "$client_pid" -n ip link set lo up
nsenter -t "$client_pid" -n ip addr add 10.223.0.2/24 dev lan1
nsenter -t "$client_pid" -n ip link set lan1 up
nsenter -t "$client_pid" -n ip route add default via 10.223.0.1
ip link add ufbr0 type veth peer name ufpeer
ip link set ufpeer netns "$server_pid"
ip addr add 172.30.109.1/29 dev ufbr0
ip link set ufbr0 up
nsenter -t "$server_pid" -n ip link set lo up
nsenter -t "$server_pid" -n ip addr add 172.30.109.2/29 dev ufpeer
nsenter -t "$server_pid" -n ip link set ufpeer up
nsenter -t "$server_pid" -n ip route add default via 172.30.109.1
sysctl -q -w net.ipv4.ip_forward=1

# Establish that both the host OUTPUT route and the routed LAN path work.
ping -n -c 1 -W 1 172.30.109.2 >/dev/null
nsenter -t "$client_pid" -n ping -n -c 1 -W 1 172.30.109.2 >/dev/null
"$install"
baseline=$(iptables -w -t raw -S)
"$install"
test "$baseline" = "$(iptables -w -t raw -S)"
ping -n -c 1 -W 1 172.30.109.2 >/dev/null
if nsenter -t "$client_pid" -n ping -n -c 1 -W 1 172.30.109.2 >/dev/null; then
  echo 'Guard failed to block routed ingress' >&2; exit 1
fi
"$reload"
test "$baseline" = "$(iptables -w -t raw -S)"
ping -n -c 1 -W 1 172.30.109.2 >/dev/null
if nsenter -t "$client_pid" -n ping -n -c 1 -W 1 172.30.109.2 >/dev/null; then
  echo 'Guard failed after actual NixOS firewall reload' >&2; exit 1
fi
"$remove"
if iptables -w -t raw -C PREROUTING -j ultrafeeder-ingress 2>/dev/null; then
  echo 'Guard cleanup failed' >&2; exit 1
fi
nsenter -t "$client_pid" -n ping -n -c 1 -W 1 172.30.109.2 >/dev/null
echo 'Verified ingress blocked before/after NixOS firewall reload, host OUTPUT allowed, install idempotent, and cleanup restores route'
