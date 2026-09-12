#!/usr/bin/env python3
"""Varga Relay: authenticated Wake-on-LAN endpoint intended for a Tailscale network."""

import hmac
import ipaddress
import json
import os
import re
import socket
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = os.environ.get("VARGA_RELAY_HOST", "0.0.0.0")
PORT = int(os.environ.get("VARGA_RELAY_PORT", "47831"))
TOKEN = os.environ.get("VARGA_RELAY_TOKEN", "")
BROADCAST = os.environ.get("VARGA_RELAY_BROADCAST", "255.255.255.255")
LAST_WAKE = {}


class Handler(BaseHTTPRequestHandler):
    server_version = "VargaRelay/1.0"

    def _reply(self, status, payload):
        data = json.dumps(payload, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        try:
            remote = ipaddress.ip_address(self.client_address[0])
            tailnet = ipaddress.ip_network("100.64.0.0/10")
            if not (remote.is_loopback or remote in tailnet):
                return self._reply(403, {"ok": False, "error": "Rete non autorizzata."})
        except ValueError:
            return self._reply(403, {"ok": False, "error": "Rete non autorizzata."})
        if self.path != "/wake":
            return self._reply(404, {"ok": False, "error": "Comando non disponibile."})
        supplied = self.headers.get("Authorization", "")
        if not TOKEN or not hmac.compare_digest(supplied, f"Bearer {TOKEN}"):
            return self._reply(401, {"ok": False, "error": "Token non valido."})
        try:
            length = min(int(self.headers.get("Content-Length", "0")), 4096)
            body = json.loads(self.rfile.read(length))
            mac = re.sub(r"[^0-9a-fA-F]", "", str(body.get("mac", ""))).upper()
            if len(mac) != 12:
                raise ValueError("Indirizzo MAC non valido.")
            now = time.monotonic()
            if now - LAST_WAKE.get(mac, 0) < 3:
                return self._reply(429, {"ok": False, "error": "Attendi tre secondi."})
            mac_bytes = bytes.fromhex(mac)
            packet = b"\xff" * 6 + mac_bytes * 16
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
                udp.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
                udp.sendto(packet, (BROADCAST, 9))
                udp.sendto(packet, (BROADCAST, 7))
            LAST_WAKE[mac] = now
            return self._reply(200, {"ok": True, "mac": mac, "broadcast": BROADCAST})
        except (ValueError, json.JSONDecodeError) as exc:
            return self._reply(400, {"ok": False, "error": str(exc)})
        except Exception:
            return self._reply(500, {"ok": False, "error": "Invio Wake-on-LAN non riuscito."})

    def do_GET(self):
        try:
            remote = ipaddress.ip_address(self.client_address[0])
            tailnet = ipaddress.ip_network("100.64.0.0/10")
            if not (remote.is_loopback or remote in tailnet):
                return self._reply(403, {"ok": False, "error": "Rete non autorizzata."})
        except ValueError:
            return self._reply(403, {"ok": False, "error": "Rete non autorizzata."})
        supplied = self.headers.get("Authorization", "")
        if not TOKEN or not hmac.compare_digest(supplied, f"Bearer {TOKEN}"):
            return self._reply(401, {"ok": False, "error": "Token non valido."})
        if self.path != "/health":
            return self._reply(404, {"ok": False, "error": "Comando non disponibile."})
        return self._reply(200, {"ok": True, "service": "VargaRelay", "version": 1})

    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args), flush=True)


if __name__ == "__main__":
    if len(TOKEN) < 32:
        raise SystemExit("Imposta VARGA_RELAY_TOKEN con almeno 32 caratteri.")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
