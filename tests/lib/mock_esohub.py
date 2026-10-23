#!/usr/bin/env python3
import base64
import email.parser
import email.policy
import http.server
import io
import json
import os
import re
import socketserver
import sys
import urllib.parse
import zipfile

root, port_file, request_log = sys.argv[1], sys.argv[2], sys.argv[3]
GOOD_USER = "Example User"
GOOD_PASS = 'p@ss"w\\rd:x'
CF_GOOD = "cfok.TEST-fixture_0123456789abcdef"
CF_UA = "Mozilla/5.0 (X11; Linux x86_64) TestBrowser/1.0"
UUID4 = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")


def approved():
    try:
        with open(os.path.join(root, "approved")) as f:
            return set(f.read().split())
    except OSError:
        return set()


def mode():
    try:
        with open(os.path.join(root, "mode")) as f:
            return f.read().strip()
    except OSError:
        return "ok"


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def record(self, extra):
        entry = {
            "method": self.command,
            "path": urllib.parse.urlsplit(self.path).path,
            "query": urllib.parse.urlsplit(self.path).query,
            "ua": self.headers.get("User-Agent", ""),
            "client": self.headers.get("X-ESO-Hub-Client-Version", ""),
            "auth": self.headers.get("Authorization", ""),
            "cookie": self.cf_cookie(),
        }
        entry.update(extra)
        with open(request_log, "a") as f:
            f.write(json.dumps(entry, sort_keys=True) + "\n")

    def send(self, code, body, ctype="application/json", challenge=False):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        if challenge:
            self.send_header("cf-mitigated", "challenge")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def cf_cookie(self):
        for part in self.headers.get("Cookie", "").split(";"):
            k, _, v = part.strip().partition("=")
            if k == "cf_clearance":
                return v
        return ""

    def gated(self):
        return mode() == "cfgate" and not (self.cf_cookie() == CF_GOOD and self.headers.get("User-Agent", "") == CF_UA)

    def challenge(self):
        self.send(403, "<!DOCTYPE html><title>Just a moment...</title>", "text/html", True)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def parts(self, raw):
        ctype = self.headers.get("Content-Type", "")
        if not ctype.startswith("multipart/form-data"):
            return []
        msg = email.parser.BytesParser(policy=email.policy.HTTP).parsebytes(
            b"Content-Type: " + ctype.encode() + b"\r\n\r\n" + raw)
        out = []
        for part in msg.iter_parts():
            payload = part.get_payload(decode=True) or b""
            item = {"name": part.get_param("name", header="content-disposition"),
                    "filename": part.get_filename() or "",
                    "type": part.get_content_type()}
            if item["filename"].endswith(".zip"):
                try:
                    with zipfile.ZipFile(io.BytesIO(payload)) as z:
                        item["entries"] = sorted(z.namelist())
                except zipfile.BadZipFile:
                    item["entries"] = "bad zip"
            elif not item["filename"]:
                item["value"] = payload.decode(errors="replace")
            else:
                item["size"] = len(payload)
            out.append(item)
        return out

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        m = mode()
        self.record({})
        if self.gated():
            return self.challenge()
        if path == "/v2/api/get-addon-versions":
            if m in ("v2block", "allblock"):
                return self.challenge()
            if m == "down":
                return self.send(500, '{"message":"Server Error"}')
            if self.headers.get("Authorization", "") == "Bearer stale-token":
                return self.send(401, '{"message":"Unauthenticated."}')
            return self.serve_file("v2.json")
        if path.startswith("/addons/download/"):
            return self.serve_file(path.lstrip("/"), "application/zip")
        self.send(404, '{"message":"Not Found"}')

    def serve_file(self, rel, ctype="application/json"):
        full = os.path.join(root, rel)
        if not os.path.isfile(full):
            return self.send(404, '{"message":"Not Found"}')
        with open(full, "rb") as f:
            self.send(200, f.read(), ctype)

    def do_POST(self):
        path = urllib.parse.urlsplit(self.path).path
        raw = self.body()
        m = mode()
        if path == "/test/approve":
            code = urllib.parse.parse_qs(raw.decode()).get("code", [""])[0]
            with open(os.path.join(root, "approved"), "a") as f:
                f.write(code + "\n")
            return self.send(200, '{"ok":true}')
        parts = self.parts(raw)
        form = {}
        if self.headers.get("Content-Type", "").startswith("application/x-www-form-urlencoded"):
            form = {k: v[0] for k, v in urllib.parse.parse_qs(raw.decode(), keep_blank_values=True).items()}
        extra = {"parts": parts} if parts else {}
        if form:
            extra["form"] = sorted(form.keys())
        auth = self.headers.get("Authorization", "")
        code = None
        if path == "/v2/api/request-token-with-code":
            try:
                code = str(json.loads(raw.decode() or "{}").get("code", ""))
            except (ValueError, AttributeError):
                code = ""
            extra["code"] = "uuid4" if UUID4.match(code) else code
            extra["ctype"] = self.headers.get("Content-Type", "")
        if auth.startswith("Basic "):
            extra["basic_user"] = base64.b64decode(auth[6:]).decode("utf-8", "replace").split(":", 1)[0]
        self.record(extra)
        if self.gated():
            return self.challenge()

        if path == "/v1/api/get-addon-versions":
            if m == "allblock":
                return self.challenge()
            if m == "down":
                return self.send(500, '{"message":"Server Error"}')
            return self.serve_file("v1.json")
        if path.startswith("/upload/"):
            names = [p["name"] for p in parts]
            if m == "v2upfail" and "archive" in names:
                return self.challenge()
            if "archive" in names or "file" in names:
                return self.send(200, '{"success":true}')
            return self.send(422, '{"message":"No file"}')
        if path == "/v2/api/request-token":
            if m in ("v2block", "allblock"):
                return self.challenge()
            user, _, pw = base64.b64decode(auth[6:]).decode("utf-8", "replace").partition(":") if auth.startswith("Basic ") else ("", "", "")
            if user == GOOD_USER and pw == GOOD_PASS:
                return self.send(200, '{"token":"tok-v2-example"}')
            return self.send(401, '{"message":"Invalid credentials"}')
        if path == "/v2/api/request-token-with-code":
            if not UUID4.match(code):
                return self.send(422, '{"message":"The code field must be a valid UUID."}')
            if code in approved():
                return self.send(200, json.dumps({"token": "tok-code-example", "username": GOOD_USER}))
            return self.send(404, '{"message":"Code not found"}')
        if path == "/v1/api/login":
            if m == "allblock":
                return self.challenge()
            if form.get("username") == GOOD_USER and form.get("password") == GOOD_PASS:
                return self.send(200, '{"success":true,"token":"tok-v1-example"}')
            return self.send(200, '{"success":false}')
        self.send(404, '{"message":"Not Found"}')


with socketserver.TCPServer(("127.0.0.1", 0), Handler) as httpd:
    with open(port_file, "w") as f:
        f.write(str(httpd.server_address[1]))
    httpd.serve_forever()
