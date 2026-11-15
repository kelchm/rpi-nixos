"""Exercise the configured image with synthetic Beast data, without internet access.

Pass JSON exported from the NixOS container definition. Uses Docker on an ARM64
Linux runner (also works with the Mac's Linux Docker VM); always removes its
containers and network. No host secrets or SDR devices are used.
"""

import json
import subprocess
import sys
import time
import uuid


def docker(*args, check=True):
    return subprocess.run(
        ["docker", *args], check=check, capture_output=True, text=True,
        timeout=180 if args[0] == "pull" else 30,
    ).stdout.strip()


# Public CPR decoding example: ICAO 40621d, near 52.26 N, 3.93 E.
# A second ICAO carries MLAT-only positions, identified by the Beast timestamp.
SOURCE = r'''
import http.server, json, socketserver, threading, time

received = set()

class Aggregator(socketserver.BaseRequestHandler):
    def handle(self):
        tail = b''
        while True:
            chunk = self.request.recv(4096)
            if not chunk:
                return
            tail += chunk
            for icao in ['40621d', '40621e']:
                if bytes.fromhex('8d' + icao) in tail:
                    received.add(icao)
            tail = tail[-64:]

def message(payload, icao):
    data = bytearray.fromhex(payload)
    data[1:4] = bytes.fromhex(icao)
    crc = int.from_bytes(data[:-3], 'big') << 24
    for bit in range(111, 23, -1):
        if crc & (1 << bit):
            crc ^= 0x1fff409 << (bit - 24)
    data[-3:] = crc.to_bytes(3, 'big')
    return bytes(data)

class Beast(socketserver.BaseRequestHandler):
    def handle(self):
        mlat = self.server.server_address[1] == 39015
        icao = '40621e' if mlat else '40621d'
        try:
            while True:
                for payload in ['8D40621D58C382D690C8AC2863A7',
                                '8D40621D58C386435CC412692AD6']:
                    stamp = 0xff004d4c4154 if mlat else int(time.monotonic() * 12000000) % (1 << 48)
                    frame = stamp.to_bytes(6, 'big') + b'\xd0' + message(payload, icao)
                    self.request.sendall(b'\x1a3' + frame.replace(b'\x1a', b'\x1a\x1a'))
                    time.sleep(0.2)
        except (BrokenPipeError, ConnectionResetError):
            pass

class Http(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        now = time.time()
        local = dict(accepted=[100, 0], strong_signals=0, signal=-12, noise=-30,
                     peak_signal=-8, samples_processed=2400000, samples_dropped=0)
        stats = dict(start=now-60, end=now, local=local, adaptive=dict(gain_db=40.2))
        data = {'last1min': stats, 'total': stats, 'latest': stats}
        if self.path == '/received.json':
            data = sorted(received)
        elif self.path.endswith('aircraft.json'):
            data = dict(now=now, messages=100, aircraft=[])
        elif self.path.endswith('receiver.json'):
            data = dict(version='fixture', refresh=1000, history=0)
        body = json.dumps(data).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass

for port in [39005, 39015]:
    server = socketserver.ThreadingTCPServer(('0.0.0.0', port), Beast)
    threading.Thread(target=server.serve_forever, daemon=True).start()
server = socketserver.ThreadingTCPServer(('0.0.0.0', 40004), Aggregator)
threading.Thread(target=server.serve_forever, daemon=True).start()
http.server.HTTPServer(('0.0.0.0', 8080), Http).serve_forever()
'''


def main():
    with open(sys.argv[1]) as stream:
        config = json.load(stream)
    suffix = uuid.uuid4().hex[:10]
    network = f"uf-test-{suffix}"
    source = f"uf-source-{suffix}"
    feeder = f"uf-feeder-{suffix}"
    image = config["image"]
    env = config["environment"]
    env.update(READSB_LAT="52.0", READSB_LON="4.0", READSB_ALT="10m",
               UUID="00000000-0000-4000-8000-000000000001")
    env["ULTRAFEEDER_CONFIG"] = env["ULTRAFEEDER_CONFIG"].replace("172.30.109.1", source)
    env["URL_1090_SIGNAL"] = f"http://{source}:8080"
    # Check the intended production destinations, then remove every upload from
    # the isolated trial. No real station identity or traffic is used in CI.
    connections = env["ULTRAFEEDER_CONFIG"].split(";")
    inputs = [f"adsb,{source},39005,beast_in", f"mlathub,{source},39015,beast_in"]
    uploads = [entry for entry in connections if entry not in inputs]
    assert uploads == [
        "adsb,in.adsb.lol,30004,beast_reduce_plus_out",
        "mlat,in.adsb.lol,31090,--privacy",
        "adsb,feed.airplanes.live,30004,beast_reduce_plus_out",
        "mlat,feed.airplanes.live,31090,--privacy",
    ], uploads
    env["ULTRAFEEDER_CONFIG"] = ";".join(inputs + [f"adsb,{source},40004,beast_reduce_plus_out"])
    try:
        docker("pull", image)
        docker("network", "create", "--internal", network)
        docker("run", "-d", "--name", source, "--network", network,
               "--entrypoint", "/usr/bin/python3", image, "-u", "-c", SOURCE)
        args = ["run", "-d", "--name", feeder, "--network", network]
        for key, value in env.items():
            args.extend(["--env", f"{key}={value}"])
        args.extend(option for option in config["extraOptions"] if not option.startswith("--ip="))
        docker(*args, image)
        fetch = (
            "import urllib.request,sys; path=sys.argv[1]; "
            "url=path if path.startswith('http://') else 'http://127.0.0.1'+path; "
            "print(urllib.request.urlopen(url, timeout=3).read().decode())"
        )
        deadline = time.monotonic() + 120
        last_error = "container did not become ready"
        while time.monotonic() < deadline:
            try:
                data = json.loads(docker("exec", feeder, "/usr/bin/python3", "-c", fetch, "/data/aircraft.json"))
                aircraft = {entry["hex"]: entry for entry in data["aircraft"]}
                radio = aircraft["40621d"]
                returned = aircraft["40621e"]
                # These two example CPR frames encode slightly different
                # positions; either can be the most recent accepted update.
                assert abs(radio["lat"] - 52.26) < 0.02, radio
                assert abs(radio["lon"] - 3.93) < 0.02, radio
                assert "lat" in returned["mlat"], returned
                assert "lat" not in radio.get("mlat", []), radio
                # Calculated positions belong on the map, never in the radio
                # stream that is subsequently sent to ADS-B/MLAT aggregators.
                raw_check = (
                    "import socket,time; s=socket.create_connection(('127.0.0.1',30005),3); "
                    "s.settimeout(3); chunks=[s.recv(4096) for _ in range(8)]; "
                    "data=b''.join(chunks); "
                    "assert bytes.fromhex('8d40621d') in data; "
                    "assert bytes.fromhex('8d40621e') not in data"
                )
                docker("exec", feeder, "/usr/bin/python3", "-c", raw_check)
                uploaded = json.loads(docker("exec", source, "/usr/bin/python3", "-c", fetch, "http://127.0.0.1:8080/received.json"))
                assert uploaded == ["40621d"], uploaded
                page = docker("exec", feeder, "/usr/bin/python3", "-c", fetch, "/")
                assert "<html" in page.lower()
                docker("exec", feeder, "/usr/bin/python3", "-c", fetch, "/graphs1090/")
                assert docker("inspect", "--format", "{{.State.OOMKilled}}", feeder) == "false"
                limits = (
                    "from pathlib import Path; "
                    "assert Path('/sys/fs/cgroup/memory.max').read_text().strip() == '335544320'; "
                    "assert Path('/sys/fs/cgroup/memory.swap.max').read_text().strip() == '0'; "
                    "assert int(Path('/proc/1/oom_score_adj').read_text()) >= 500"
                )
                docker("exec", feeder, "/usr/bin/python3", "-c", limits)
                print("Verified map, graphs, radio/MLAT positions, and an outgoing feed excluding MLAT results")
                return
            except (subprocess.CalledProcessError, ValueError, KeyError, AssertionError) as error:
                last_error = str(error)
                time.sleep(1)
        raise AssertionError(last_error)
    except Exception:
        print(docker("logs", feeder, check=False), file=sys.stderr)
        print(docker("logs", source, check=False), file=sys.stderr)
        raise
    finally:
        docker("rm", "-f", feeder, source, check=False)
        docker("network", "rm", network, check=False)


if __name__ == "__main__":
    main()
