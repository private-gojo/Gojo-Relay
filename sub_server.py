# =========================
# SUB_SERVER
# Purpose: Generates the dynamic VLESS subscription link (/sub endpoint)
# Runs on 127.0.0.1:8081, proxied by nginx
# =========================

import os
import json
import base64
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler

class DynamicSubService(BaseHTTPRequestHandler):
    def do_GET(self):
        # =========================
        # STEP 1: Get the actual Cloud Run domain the client hit
        # =========================
        raw_host = self.headers.get("Host", "localhost")
        current_host = raw_host.split(":")[0]

        # =========================
        # STEP 2: Read UUID and path from runtime.json
        # (written by entrypoint.sh at container startup)
        # =========================
        uuid = ""
        full_path = ""
        try:
            with open("/etc/xray/runtime.json", "r") as f:
                rdata = json.load(f)
                uuid = rdata.get("uuid", "")
                full_path = rdata.get("path", "")
        except Exception:
            pass

        encoded_path = urllib.parse.quote(full_path, safe="")

        # =========================
        # STEP 3: SNI and IP lists (env vars, with fallback defaults)
        # =========================
        sni_env = os.getenv("GOJO_SNI_LIST", "firebaseremoteconfigrealtime.googleapis.com firebase-settings.crashlytics.com fcmtoken.googleapis.com")
        ip_env = os.getenv("GOJO_SUB_IP_LIST", "172.217.26.227 142.250.4.101 74.125.200.101")

        sni_list = sni_env.split()
        ip_list = ip_env.split()

        # =========================
        # STEP 4: Generate VLESS URIs (SNI x IP combinations)
        # =========================
        sub_lines = []
        count = 1
        for sni in sni_list:
            for ip in ip_list:
                uri = f"vless://{uuid}@{ip}:443?encryption=none&security=tls&sni={sni}&type=ws&host={current_host}&path={encoded_path}#Gojo-Relay-{count}"
                sub_lines.append(uri)
                count += 1

        payload = "\n".join(sub_lines)
        b64_output = base64.b64encode(payload.encode("utf-8"))

        # =========================
        # STEP 5: Send base64 response back to nginx
        # =========================
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(b64_output)))
        self.end_headers()
        self.wfile.write(b64_output)

    def log_message(self, format, *args):
        # Mute console access logs to keep Docker output clean
        return

if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", 8081), DynamicSubService)
    server.serve_forever()
