#!/usr/bin/env python3
import selectors
import signal
import socket
import sys
import time


def main() -> int:
    if len(sys.argv) not in (4, 5):
        print(
            "usage: tcp_blackout_proxy.py <listen_port> <target_host> <target_port> [blackout_ms]",
            file=sys.stderr,
        )
        return 2

    listen_port = int(sys.argv[1])
    target_host = sys.argv[2]
    target_port = int(sys.argv[3])
    blackout_ms = float(sys.argv[4]) if len(sys.argv) == 5 else 75.0

    sel = selectors.DefaultSelector()
    sockets = set()
    listener = None
    peer = {}
    running = True
    blackout_until = 0.0

    def unregister_and_close(sock):
        if sock is None:
            return
        peer.pop(sock, None)
        try:
            sel.unregister(sock)
        except Exception:
            pass
        try:
            sock.close()
        except Exception:
            pass
        sockets.discard(sock)

    def close_all():
        for sock in list(sockets):
            unregister_and_close(sock)

    def close_active_connections():
        for sock in list(sockets):
            if sock is listener:
                continue
            unregister_and_close(sock)

    def bind_listener():
        nonlocal listener
        new_listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        new_listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        new_listener.bind(("127.0.0.1", listen_port))
        new_listener.listen()
        new_listener.setblocking(False)
        listener = new_listener
        sockets.add(new_listener)
        sel.register(new_listener, selectors.EVENT_READ, ("accept", None))

    def stop(_signum, _frame):
        nonlocal running
        running = False
        close_all()

    def flap(_signum, _frame):
        nonlocal blackout_until
        blackout_until = time.time() + (blackout_ms / 1000.0)
        close_active_connections()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGUSR1, flap)

    bind_listener()
    print(
        f"proxy listening on 127.0.0.1:{listen_port} -> {target_host}:{target_port} blackout_ms={blackout_ms}",
        flush=True,
    )

    try:
        while running:
            for key, _ in sel.select(timeout=0.2):
                sock = key.fileobj
                kind, _ = key.data

                if kind == "accept":
                    if time.time() < blackout_until:
                        try:
                            client, _ = sock.accept()
                            client.close()
                        except OSError:
                            pass
                        continue

                    client, _ = sock.accept()
                    upstream = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    try:
                        upstream.connect((target_host, target_port))
                    except OSError:
                        client.close()
                        upstream.close()
                        continue
                    client.setblocking(False)
                    upstream.setblocking(False)
                    sockets.update({client, upstream})
                    peer[client] = upstream
                    peer[upstream] = client
                    sel.register(client, selectors.EVENT_READ, ("copy", None))
                    sel.register(upstream, selectors.EVENT_READ, ("copy", None))
                    continue

                try:
                    data = sock.recv(65536)
                except OSError:
                    data = b""

                other = peer.get(sock)
                if not data or other is None:
                    unregister_and_close(sock)
                    unregister_and_close(other)
                    continue

                try:
                    other.sendall(data)
                except OSError:
                    unregister_and_close(sock)
                    unregister_and_close(other)
    finally:
        close_all()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
