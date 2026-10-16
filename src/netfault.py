"""Test-only TCP proxy that breaks the network on a schedule (stage 1d: the stream buffer and reconnect).

Usage: python src/netfault.py LISTEN_PORT TARGET_PORT "30:reset:10,90:blackhole:30"
  Times are seconds after the first client connects.
  reset     — close every connection at once and refuse new ones for the given seconds (the server or link is gone).
  blackhole — stop passing bytes in both directions and ignore new connections for the given seconds, then close the
              stuck connections (mobile data that silently stops: no error reaches the client).
"""
import socket, sys, threading, time

listen_port, target_port = int(sys.argv[1]), int(sys.argv[2])
events = [(float(a), m, float(d)) for a, m, d in (e.split(':') for e in sys.argv[3].split(',') if e)]
t0 = None; conns = []; lock = threading.Lock()

def mode(now):
    if t0 is None: return 'ok'
    for a, m, d in events:
        if a <= now - t0 < a + d: return m
    return 'ok'

def log(*x): print(f'{time.time() - (t0 or time.time()):7.1f}', *x, flush=True)

def pump(a, b, pair):
    try:
        while True:
            while mode(time.time()) == 'blackhole' and not pair['dead']: time.sleep(0.05)
            if pair['dead']: break
            x = a.recv(65536)
            if not x: break
            if mode(time.time()) == 'blackhole': pair['held'].append((b, x)); continue
            b.sendall(x)
    except Exception: pass
    pair['dead'] = True
    for s in (a, b):
        try: s.close()
        except Exception: pass

def watchdog():
    last = 'ok'
    while True:
        m = mode(time.time())
        if m != last:
            log('network', m)
            if m == 'reset' or (last == 'blackhole' and m == 'ok'):
                with lock:
                    for p in conns:
                        p['dead'] = True
                        for s in p['socks']:
                            try: s.shutdown(socket.SHUT_RDWR); s.close()
                            except Exception: pass
                    conns.clear()
            last = m
        time.sleep(0.02)

srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); srv.bind(('127.0.0.1', listen_port)); srv.listen(8)
threading.Thread(target=watchdog, daemon=True).start()
while True:
    c, _ = srv.accept()
    if t0 is None: t0 = time.time(); log('first client')
    m = mode(time.time())
    if m != 'ok': log('refused new connection (', m, ')'); c.close(); continue
    try: u = socket.create_connection(('127.0.0.1', target_port), timeout=3)
    except Exception as e: log('server not ready', e); c.close(); continue
    u.settimeout(None); log('connection opened')
    pair = {'dead': False, 'held': [], 'socks': (c, u)}
    with lock: conns.append(pair)
    threading.Thread(target=pump, args=(c, u, pair), daemon=True).start()
    threading.Thread(target=pump, args=(u, c, pair), daemon=True).start()
