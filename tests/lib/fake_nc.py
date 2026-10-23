#!/usr/bin/env python3
import os, socket, sys
args = sys.argv[1:]
style = os.environ.get("NC_STYLE", "openbsd")
if args == ["-h"]:
    print("[v1.10-47]\n -q secs quit after EOF on stdin" if style == "traditional" else "usage: nc [-46CDdFhklNnrStUuvZz] [-I length]")
    sys.exit(1)
if style == "openbsd" and len(args) == 3 and args[0] == "-l":
    host, port = args[1], int(args[2])
elif style == "traditional" and len(args) == 5 and args[:2] == ["-l", "-s"] and args[3] == "-p":
    host, port = args[2], int(args[4])
elif style == "traditional" and len(args) == 3 and args[0] == "-l":
    host, port = "127.0.0.1", 0
else:
    sys.exit(1)
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((host, port))
s.listen(1)
c, _ = s.accept()
s.close()
reply = sys.stdin.buffer.read()
c.settimeout(5)
data = b""
try:
    while b"\r\n\r\n" not in data:
        part = c.recv(4096)
        if not part:
            break
        data += part
except OSError:
    pass
sys.stdout.buffer.write(data)
sys.stdout.flush()
try:
    c.sendall(reply)
except OSError:
    pass
c.close()
