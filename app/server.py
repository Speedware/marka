#!/usr/bin/env python3
"""Marka: local converter of Chestny Znak marking codes from PDF to CSV.

Starts an HTTP server on 127.0.0.1 and opens the page in the browser.
If the server is already running, only opens the page.
The server exits by itself once the page has been closed for IDLE_TIMEOUT seconds.

Errors are returned as codes; the page translates them for the user.
"""

import io
import json
import os
import re
import sys
import threading
import time
import urllib.parse
import urllib.request
import webbrowser
import zipfile
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import fitz  # PyMuPDF
import numpy as np
import zxingcpp

HOST = "127.0.0.1"
PORT = int(os.environ.get("MARKA_PORT", "8765"))
URL = f"http://{HOST}:{PORT}/"
APP_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(APP_DIR)
ICON_PATH = os.path.join(ROOT_DIR, "marka.svg")
SIGNATURE = "marka-ok"
IDLE_TIMEOUT = 6 * 60  # background tabs ping at most once a minute
MAX_UPLOAD = 500 * 1024 * 1024

GS = "\x1d"
BOM = "\ufeff"
FORMATS = zxingcpp.BarcodeFormat.DataMatrix | zxingcpp.BarcodeFormat.QRCode

last_seen = time.monotonic()


class UserError(Exception):
    """An error the page shows to the user; args[0] is the error code."""


# ---------- decoding ----------

def _scan(page, dpi):
    pix = page.get_pixmap(dpi=dpi, colorspace=fitz.csGRAY, alpha=False)
    img = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.stride)[:, : pix.width]
    results = zxingcpp.read_barcodes(img, formats=FORMATS, text_mode=zxingcpp.TextMode.Plain)
    # reading order: top to bottom, left to right
    results.sort(key=lambda r: (round(r.position.top_left.y / 40), r.position.top_left.x))
    return [r.text.lstrip(GS) for r in results if r.text]


def decode_pdf(data):
    try:
        doc = fitz.open(stream=data, filetype="pdf")
    except Exception:
        raise UserError("not_pdf")
    if doc.needs_pass:
        raise UserError("password")
    codes = []
    for page in doc:
        found = _scan(page, 300)
        if not found:
            found = _scan(page, 600)  # tiny codes or low-quality scans
        codes.extend({"code": c, "page": page.number + 1} for c in found)
    return {"pages": doc.page_count, "codes": codes}


# ---------- export ----------

def split_code(code):
    """GTIN and serial number from a code shaped like 01<GTIN14>21<serial><GS>..."""
    m = re.match(r"^01(\d{14})21([^\x1d]+)", code)
    if not m:
        return "", ""
    serial = m.group(2)
    if GS not in code:
        serial = ""  # without a separator the end of the serial number is unknown
    return m.group(1), serial


def format_code(code, gs_mode):
    if gs_mode == "remove":
        return code.replace(GS, "")
    if gs_mode == "short":
        gtin, serial = split_code(code)
        return f"01{gtin}21{serial}" if serial else code
    return code


def quote(cell):
    if any(ch in cell for ch in ',;\t"\r\n'):
        return '"' + cell.replace('"', '""') + '"'
    return cell


def build_csv(rows, opts):
    """rows: [(file name, page, code)]"""
    delimiter = {"semicolon": ";", "comma": ",", "tab": "\t"}.get(opts.get("delimiter"), ";")
    table = opts.get("content") == "table"
    lines = [["File", "Page", "Code", "GTIN", "Serial"]] if table else []
    for name, page, code in rows:
        value = format_code(code, opts.get("gs"))
        if table:
            lines.append([name, str(page), value, *split_code(code)])
        else:
            lines.append([value])
    if opts.get("quotes") != "none":
        # Excel and Numbers guess the delimiter (comma or semicolon) themselves,
        # so quote a cell containing either of them, not only the chosen one
        lines = [[quote(cell) for cell in line] for line in lines]
    # same as the Chestny Znak export: \n between lines, no trailing \n
    text = "\n".join(delimiter.join(line) for line in lines)
    # the table may hold non-ASCII PDF names, Excel needs a BOM for them;
    # in a codes-only file a BOM would corrupt the first code
    return ((BOM if table else "") + text).encode("utf-8")


def safe_name(name):
    name = re.sub(r"\.pdf$", "", name, flags=re.I)
    name = re.sub(r'[\\/:*?"<>|\x00-\x1f]+', "_", name).strip(" .")
    return name[:120] or "codes"


def unique(name, used):
    base, n = name, 2
    while name in used:
        name = f"{base} ({n})"
        n += 1
    used.add(name)
    return name


def export(payload):
    opts = payload.get("options", {})
    mode = payload.get("mode", "single")
    files = payload.get("files", [])
    seen = set()
    groups = []  # [(file name, [(name, page, code)])]
    for f in files:
        rows = []
        for c in f.get("codes", []):
            if opts.get("dedupe", True):
                if c["code"] in seen:
                    continue
                seen.add(c["code"])
            rows.append((f["name"], c["page"], c["code"]))
        groups.append((f["name"], rows))

    stamp = datetime.now().strftime("%Y-%m-%d_%H-%M")
    if mode == "single":
        rows = [r for _, g in groups for r in g]
        name = f"{safe_name(files[0]['name'])}.csv" if len(files) == 1 else f"codes_{stamp}.csv"
        return name, "text/csv", build_csv(rows, opts)

    used, out = set(), []
    for fname, rows in groups:
        if mode == "per-file":
            if rows:
                out.append((unique(safe_name(fname), used) + ".csv", build_csv(rows, opts)))
        else:  # per-code
            for i, row in enumerate(rows, 1):
                gtin, _ = split_code(row[2])
                label = f"{safe_name(fname)}_{i:04d}" + (f"_{gtin}" if gtin else "")
                out.append((unique(label, used) + ".csv", build_csv([row], opts)))
    if len(out) == 1:
        return out[0][0], "text/csv", out[0][1]
    zbuf = io.BytesIO()
    with zipfile.ZipFile(zbuf, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in out:
            z.writestr(name, data)
    return f"codes_{stamp}.zip", "application/zip", zbuf.getvalue()


# ---------- HTTP ----------

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, code, body, ctype, extra=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj, code=200):
        self._send(code, json.dumps(obj).encode(), "application/json; charset=utf-8")

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_UPLOAD:
            raise UserError("too_large")
        return self.rfile.read(length)

    def _local_origin(self):
        # keep other websites from calling the server through the browser
        origin = self.headers.get("Origin")
        return origin in (None, URL.rstrip("/"), f"http://localhost:{PORT}")

    def do_GET(self):
        global last_seen
        last_seen = time.monotonic()
        path = urllib.parse.urlparse(self.path).path
        if path == "/":
            with open(os.path.join(APP_DIR, "index.html"), "rb") as f:
                self._send(200, f.read(), "text/html; charset=utf-8")
        elif path == "/icon.svg" and os.path.exists(ICON_PATH):
            with open(ICON_PATH, "rb") as f:
                self._send(200, f.read(), "image/svg+xml")
        elif path == "/api/ping":
            self._send(200, SIGNATURE.encode(), "text/plain")
        else:
            self._send(404, b"Not found", "text/plain")

    def do_POST(self):
        global last_seen
        last_seen = time.monotonic()
        if not self._local_origin():
            return self._send(403, b"Forbidden", "text/plain")
        path = urllib.parse.urlparse(self.path).path
        try:
            if path == "/api/decode":
                self._json(decode_pdf(self._body()))
            elif path == "/api/export":
                name, ctype, data = export(json.loads(self._body()))
                self._send(200, data, ctype, {"X-Filename": urllib.parse.quote(name)})
            else:
                self._send(404, b"Not found", "text/plain")
        except UserError as e:
            self._json({"error": e.args[0]}, 400)
        except Exception as e:
            print(f"Error on {path}: {e!r}", flush=True)
            self._json({"error": "internal"}, 500)


def already_running():
    try:
        with urllib.request.urlopen(URL + "api/ping", timeout=1) as r:
            return r.read().decode() == SIGNATURE
    except Exception:
        return False


def watchdog(server):
    while True:
        time.sleep(30)
        if time.monotonic() - last_seen > IDLE_TIMEOUT:
            server.shutdown()
            return


def main():
    if sys.stdout is None:  # Windows: pythonw.exe runs without a console
        log = open(os.path.join(ROOT_DIR, "marka.log"), "w", encoding="utf-8", buffering=1)
        sys.stdout = sys.stderr = log
    if already_running():
        webbrowser.open(URL)
        return
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    threading.Thread(target=watchdog, args=(server,), daemon=True).start()
    if "--no-browser" not in sys.argv:
        threading.Timer(0.3, webbrowser.open, args=(URL,)).start()
    print(f"Marka is running: {URL}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
