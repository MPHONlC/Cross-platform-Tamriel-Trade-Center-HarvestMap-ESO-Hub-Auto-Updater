#!/usr/bin/env python3
import http.server
import socketserver
import sys
import urllib.parse

root, port_file, request_log = sys.argv[1], sys.argv[2], sys.argv[3]


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=root, **kwargs)

    def translate_path(self, path):
        parsed = urllib.parse.urlsplit(path)
        route = parsed.path
        if route.startswith("/downloads/getfile.php"):
            query = urllib.parse.parse_qs(parsed.query)
            route = "/getfile/" + query.get("id", ["0"])[0] + ".zip"
        return super().translate_path(route)

    def log_message(self, fmt, *args):
        with open(request_log, "a") as f:
            f.write(self.path + "\n")


with socketserver.TCPServer(("127.0.0.1", 0), Handler) as httpd:
    with open(port_file, "w") as f:
        f.write(str(httpd.server_address[1]))
    httpd.serve_forever()
