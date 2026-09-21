#!/usr/bin/env python3
"""
latch-android-bridge.py — TCP<->Unix-abstract-socket bridge for Chrome's
DevTools protocol on Android.

Why this exists: Android Chrome never opens a real TCP port for CDP, even
with --remote-debugging-port set. It always listens on a Linux ABSTRACT
unix socket named "chrome_devtools_remote" (the classic "adb forward
tcp:9333 localabstract:chrome_devtools_remote" target). An SSH -L tunnel
can only forward a TCP port to another TCP port on the remote side — it
has no notion of a unix socket at all — so latch-tunnel.sh's normal
`ssh -L 9333:127.0.0.1:9333` has nothing to connect to on an Android
anchor without something on that side first exposing the abstract socket
as a real TCP port. This script is that something: a tiny stdlib-only
daemon that accepts local TCP connections and pipes them 1:1 into the
abstract socket, so the rest of the Latch pipeline (tunnel/status/stop)
works completely unmodified once this is running.

Runs under Termux's python3 (present by default on any Termux install),
launched as root via `su` only to read/write /data/local/tmp and to
force-stop/relaunch Chrome — the bridge process itself needs no special
privilege beyond an app-visible unix-abstract-socket connect, which is
unrestricted by SELinux for any process in the same user (root covers
this unconditionally, which is why Latch's existing SSH-to-a-rooted-
device model already assumes root elsewhere, e.g. pixy).

Usage: python3 latch-android-bridge.py [local_port] [socket_name]
"""
import socket
import sys
import threading

LOCAL_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9333
SOCKET_NAME = sys.argv[2] if len(sys.argv) > 2 else "chrome_devtools_remote"


def pipe(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        for s in (src, dst):
            try:
                s.close()
            except OSError:
                pass


def handle(conn):
    upstream = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        upstream.connect("\0" + SOCKET_NAME)
    except OSError as e:
        print(f"[latch-bridge] connect to abstract socket '{SOCKET_NAME}' failed: {e}", flush=True)
        conn.close()
        return
    threading.Thread(target=pipe, args=(conn, upstream), daemon=True).start()
    pipe(upstream, conn)


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", LOCAL_PORT))
    srv.listen(16)
    print(f"[latch-bridge] listening on 127.0.0.1:{LOCAL_PORT} -> abstract:{SOCKET_NAME}", flush=True)
    while True:
        conn, _ = srv.accept()
        threading.Thread(target=handle, args=(conn,), daemon=True).start()


if __name__ == "__main__":
    main()
