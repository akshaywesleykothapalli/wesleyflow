"""Disposable denial probes against loopback discard ports; never a remote server."""
import errno,json,socket
out={}
for name,family,address in [('ipv4Denied',socket.AF_INET,('127.0.0.1',9)),('ipv6Denied',socket.AF_INET6,('::1',9))]:
    sock=None
    try:
        sock=socket.socket(family);sock.settimeout(1);sock.connect(address);out[name]=False
    except OSError as e:out[name]=e.errno in [errno.EPERM,errno.EACCES]
    finally:
        if sock:sock.close()
print(json.dumps(out));raise SystemExit(0 if all(out.values()) else 2)
