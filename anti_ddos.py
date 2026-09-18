#!/usr/bin/env python3
# =========================
# ANTI-DDOS FORTRESS
# Edge proxy on port 8080 (public-facing) in front of Nginx (8082)
# Filters L7 floods before they reach Nginx/Xray - reads the initial
# HTTP request with the public read() API (no private buffer access),
# checks it against the whitelist, then relays raw bytes to Nginx
# =========================

import asyncio, os, socket

LISTEN_PORT = int(os.environ.get("PORT", "8080"))
BACKEND_PORT = 8082  # NGINX INTERNAL PORT
BUF_SIZE = 131072

# In-memory, per-instance - resets on restart, not shared across Cloud
# Run instances. Acceptable here since each instance independently
# bans an attacker's IP once it hits that instance.
BANNED_IPS = set()
ACTIVE_CONNS = 0
MAX_CONNS = 950

# Must match the location blocks in nginx.conf
ALLOWED_PREFIXES = (b"/", b"/sub", b"/gojo/infinity-limitless", b"/runtime.json", b"/health")

def get_real_ip(headers_bytes, raw_ip):
    # Extracts the real client IP from X-Forwarded-For so Nginx doesn't
    # just see 127.0.0.1 for every connection
    for line in headers_bytes:
        if line.lower().startswith(b"x-forwarded-for:"):
            return line.split(b":", 1)[1].split(b",")[0].strip().decode('utf-8', 'ignore')
    return raw_ip

def optimize_socket(sock: socket.socket):
    if not sock: return
    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, BUF_SIZE)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, BUF_SIZE)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)

async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    global ACTIVE_CONNS
    peer = writer.get_extra_info("peername")
    raw_socket_ip = peer[0] if peer else "127.0.0.1"

    if ACTIVE_CONNS >= MAX_CONNS:
        writer.close(); return

    ACTIVE_CONNS += 1
    client_ip = raw_socket_ip

    try:
        # -------------------------
        # Read the initial request using the public read() API in a loop,
        # not readuntil() + private _buffer access. This accumulates
        # whatever arrives (headers, and possibly the start of payload
        # data in the same TCP segment) into one buffer we forward whole,
        # so nothing gets lost or corrupted before it reaches Nginx/Xray.
        # Anti-Slowloris: 2-second strict timeout per read.
        # -------------------------
        raw = b""
        while b"\r\n\r\n" not in raw:
            chunk = await asyncio.wait_for(reader.read(65536), timeout=2.0)
            if not chunk:
                raise ValueError("Incomplete")
            raw += chunk
            if len(raw) > 16384:  # Anti header-flood: drop oversized headers
                raise ValueError("Oversized")

        header_end = raw.find(b"\r\n\r\n")
        headers_part = raw[:header_end]
        lines = headers_part.split(b"\r\n")

        client_ip = get_real_ip(lines[1:], raw_socket_ip)

        if client_ip in BANNED_IPS:
            writer.close(); return

        req_line = lines[0].split(b" ")
        if len(req_line) < 2:
            raise ValueError("Malformed")

        base_path = req_line[1].split(b"?")[0]

        # -------------------------
        # Fast-drop banishment: any path outside the known whitelist gets
        # the IP banned in this instance's memory and the connection closed
        # -------------------------
        if base_path != b"/" and not base_path.startswith(ALLOWED_PREFIXES):
            BANNED_IPS.add(client_ip)
            writer.write(b"HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n")
            await writer.drain(); writer.close(); return

        # -------------------------
        # Clean traffic - open the connection to Nginx and relay
        # -------------------------
        try:
            backend_reader, backend_writer = await asyncio.open_connection("127.0.0.1", BACKEND_PORT)
            optimize_socket(backend_writer.get_extra_info("socket"))
            optimize_socket(writer.get_extra_info("socket"))
        except Exception:
            writer.close(); return

        # Forward the whole initial chunk (headers + any leftover payload
        # that arrived in the same read) - nothing is split or extracted
        # separately, so nothing can be lost between reader and backend_writer
        backend_writer.write(raw)
        await backend_writer.drain()

        async def relay(r, w):
            try:
                while True:
                    data = await r.read(BUF_SIZE)
                    if not data: break
                    w.write(data); await w.drain()
            except Exception: pass
            finally: w.close()

        await asyncio.gather(relay(reader, backend_writer), relay(backend_reader, writer), return_exceptions=True)

    except asyncio.TimeoutError:
        BANNED_IPS.add(client_ip)
    except Exception:
        pass
    finally:
        ACTIVE_CONNS -= 1
        writer.close()

async def main():
    server = await asyncio.start_server(handle_client, "0.0.0.0", LISTEN_PORT)
    async with server: await server.serve_forever()

if __name__ == "__main__":
    import gc
    gc.set_threshold(50_000, 500, 100)
    asyncio.run(main())
