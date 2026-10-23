#!/usr/bin/env python3
import http.server
import json
import os
import socketserver
import sys
import urllib.parse

root, port_file, request_log = sys.argv[1], sys.argv[2], sys.argv[3]
SHA = "0123456789abcdef0123456789abcdef01234567"
WF = ".github/workflows/"


def mode():
    try:
        with open(os.path.join(root, "mode")) as f:
            return f.read().strip()
    except OSError:
        return "ok"


def runs(refreshing):
    def run(path, status):
        return {"id": len(path), "name": path, "path": WF + path, "status": status,
                "conclusion": None if status != "completed" else "success",
                "repository": {"full_name": "example/example"}}
    items = [run("keep-alive.yml", "in_progress"),
             run("data-tables-refresh.yml", "in_progress" if refreshing else "completed"),
             run("console-data-refresh.yml", "completed"),
             run("data-release.yml", "completed")]
    body = {"total_count": len(items), "workflow_runs": items}
    if refreshing:
        return json.dumps(body, separators=(",", ":"))
    return json.dumps(body, indent=2)


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def send(self, code, body, ctype="application/json"):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        m = mode()
        with open(request_log, "a") as f:
            f.write(json.dumps({"path": path, "accept": self.headers.get("Accept", "")}) + "\n")
        if path.startswith("/repos/") and m == "apidown":
            return self.send(500, '{"message":"Server Error"}')
        if path.startswith("/repos/") and path.endswith("/actions/runs"):
            return self.send(200, runs(m == "refreshing"))
        if path.startswith("/repos/") and path.endswith("/commits/main"):
            return self.send(200, json.dumps({"sha": SHA, "commit": {"tree": {"sha": "f" * 40}}}, indent=2))
        if path.startswith("/repos/") and path.endswith("/releases/latest"):
            try:
                with open(os.path.join(root, "selfver")) as f:
                    ver = f.read().strip()
            except OSError:
                ver = "2026.09.30.16.00"
            base = "http://127.0.0.1:%s" % self.server.server_address[1]
            body = {"tag_name": "Version-" + ver, "name": ver,
                    "assets": [{"name": "Source code.zip", "browser_download_url": base + "/ghdl/Source-code.zip"},
                               {"name": "Tamriel_Trade_Center_Auto-Updater.zip", "browser_download_url": base + "/ghdl/Tamriel_Trade_Center_Auto-Updater.zip"}]}
            return self.send(200, json.dumps(body, indent=2))
        if path == "/ghdl/Tamriel_Trade_Center_Auto-Updater.zip":
            full = os.path.join(root, "self.zip")
            if os.path.isfile(full):
                with open(full, "rb") as f:
                    return self.send(200, f.read(), "application/zip")
            return self.send(404, "no asset", "text/plain")
        if "/DATA/" in path:
            name = path.rsplit("/", 1)[1]
            if m == "rawfail" and name == "KnownLibraries.lua":
                return self.send(404, "404: Not Found", "text/plain")
            full = os.path.join(root, "data", name)
            if os.path.isfile(full):
                with open(full, "rb") as f:
                    return self.send(200, f.read(), "text/plain; charset=utf-8")
        self.send(404, '{"message":"Not Found"}')


with socketserver.TCPServer(("127.0.0.1", 0), Handler) as httpd:
    with open(port_file, "w") as f:
        f.write(str(httpd.server_address[1]))
    httpd.serve_forever()
