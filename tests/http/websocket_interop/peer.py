# A WebSocket echo server with the standard library only, for one
# connection: it checks the handshake of the client, answers with the
# subprotocol "echo", echoes the messages (unfragmented, as the client
# sends them) and answers the close.  It prints its port, then what it saw.
import base64, hashlib, socket, struct, sys

GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
srv = socket.socket()
srv.bind(("127.0.0.1", 0))
srv.listen(1)
print("port", srv.getsockname()[1], flush=True)
conn, _ = srv.accept()
conn.settimeout(10)
buf = b""
while b"\r\n\r\n" not in buf:
    buf += conn.recv(4096)
head, buf = buf.split(b"\r\n\r\n", 1)
lines = head.decode().split("\r\n")
fields = {k.strip().lower(): v.strip() for k, v in (l.split(":", 1) for l in lines[1:])}
print("request:", lines[0])
for k in ("upgrade", "connection", "sec-websocket-version", "sec-websocket-protocol"):
    print(" ", k, "=", fields.get(k))
key = fields["sec-websocket-key"]
print("  key is 16 bytes:", len(base64.b64decode(key)) == 16)
accept = base64.b64encode(hashlib.sha1(key.encode() + GUID).digest()).decode()
conn.sendall(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
              "Sec-WebSocket-Accept: " + accept + "\r\nSec-WebSocket-Protocol: echo\r\n\r\n").encode())

def take(n):
    global buf
    while len(buf) < n:
        more = conn.recv(65536)
        if not more:
            raise EOFError
        buf += more
    out, buf = buf[:n], buf[n:]
    return out

def frame(b0, payload):
    n = len(payload)
    if n < 126:
        h = struct.pack("!BB", b0, n)
    elif n < 65536:
        h = struct.pack("!BBH", b0, 126, n)
    else:
        h = struct.pack("!BBQ", b0, 127, n)
    return h + payload

keys = set()
while True:
    b0, b1 = take(2)
    n = b1 & 0x7F
    if n == 126:
        n = struct.unpack("!H", take(2))[0]
    elif n == 127:
        n = struct.unpack("!Q", take(8))[0]
    if not b1 & 0x80:
        print("an unmasked frame from the client")
        break
    mask = take(4)
    keys.add(mask)
    data = bytes(c ^ mask[i % 4] for i, c in enumerate(take(n)))
    op = b0 & 0x0F
    if op == 8:
        code = struct.unpack("!H", data[:2])[0]
        print("close from the client:", code, data[2:].decode())
        conn.sendall(frame(0x88, data[:2]))
        break
    print("message: opcode", op, "fin", bool(b0 & 0x80), "length", n)
    conn.sendall(frame(0x80 | op, data))
print("masking keys all different:", len(keys) > 1)
conn.close()
