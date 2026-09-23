"""Local browser API for Map Studio. Run: python tools/mapstudio/server.py"""

from __future__ import annotations

import json
import mimetypes
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from engine import LAYERS, ROOT, kind, studio
from sprites import sprites

HERE = Path(__file__).resolve().parent
MAPCORE_WASM = ROOT / "tools/mapcore/target/wasm32-unknown-unknown/release/deepquarry_mapcore.wasm"
_wasm_lock = threading.Lock()


def wasm_bytes():
    with _wasm_lock:
        sources = (ROOT / "tools/mapcore/src/lib.rs", ROOT / "tools/mapcore/src/network.rs",
                   ROOT / "tools/mapcore/Cargo.toml")
        if not MAPCORE_WASM.is_file() or any(path.stat().st_mtime_ns > MAPCORE_WASM.stat().st_mtime_ns
                                             for path in sources):
            build = subprocess.run(["cargo", "build", "--quiet", "--release",
                                    "--target", "wasm32-unknown-unknown", "--lib",
                                    "--manifest-path", str(ROOT / "tools/mapcore/Cargo.toml")],
                                   cwd=ROOT, capture_output=True, text=True, timeout=180)
            if build.returncode:
                raise RuntimeError("Rust browser core build failed: " + build.stderr[-2000:])
        return MAPCORE_WASM.read_bytes()


def dispatch(method, args):
    if method == "maps":
        return {"maps": studio.maps()}
    if method == "info":
        _, m, revision = studio.read(args["map"])
        return {"size": list(m.size), "revision": revision}
    if method == "inspect":
        return studio.inspect(args["map"], args["rect"])
    if method == "atlas":
        atoms = args["atoms"]
        if not isinstance(atoms, list) or len(atoms) > 5000 or any(not isinstance(atom, str) for atom in atoms):
            raise ValueError("Atlas needs at most 5,000 atom paths.")
        return sprites.atlas(atoms)
    if method == "catalog":
        _, m, revision = studio.read(args["map"])
        paths = studio.catalog_for_revision(m, revision)
        layer, query = args.get("layer"), args.get("query", "").lower()
        if layer:
            if layer not in LAYERS:
                raise ValueError("Unknown layer.")
            paths = [path for path in paths if kind(path) == layer]
        if query:
            paths = [path for path in paths if query in path.lower()]
        return {"paths": sorted(paths)[:500]}
    if method == "check":
        return studio.check_systems(args["map"], args["rect"])
    if method == "network_component":
        return studio.network_component(args["map"], args["at"], args["atom"], args.get("operations"))
    if method == "preview":
        return studio.preview(args["map"], args["operations"])
    if method == "draft":
        return studio.draft(args["map"], args["operations"])
    if method == "commit":
        return studio.commit(args["preview_id"])
    if method == "activity":
        return studio.activity()
    if method == "dismiss":
        return studio.dismiss(args["preview_id"])
    if method == "undo":
        return studio.undo()
    raise ValueError("Unknown API method.")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        if self.path.startswith(("/sprite", "/atlas")) or self.path == "/api":
            return
        sys.stderr.write("Map Studio: " + format % args + "\n")

    def _json(self, status, data):
        payload = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self):
        if urlparse(self.path).path != "/api":
            self._json(404, {"error": "Not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length > 2_000_000:
                raise ValueError("Request too large.")
            request = json.loads(self.rfile.read(length))
            self._json(200, dispatch(request["method"], request.get("args", {})))
        except (ValueError, KeyError, TypeError) as exc:
            self._json(400, {"error": str(exc)})
        except Exception as exc:
            self._json(500, {"error": f"Server error: {exc}"})

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/mapcore.wasm":
            try:
                payload = wasm_bytes()
            except (RuntimeError, subprocess.TimeoutExpired, FileNotFoundError) as error:
                self.send_error(503, str(error))
                return
            self.send_response(200)
            self.send_header("Content-Type", "application/wasm")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(payload)
            return
        if path == "/atlas":
            key = parse_qs(parsed.query).get("id", [""])[0]
            payload = sprites.atlas_bytes(key)
            if payload is None:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "public, max-age=3600")
            self.end_headers()
            self.wfile.write(payload)
            return
        if path == "/sprite":
            atom = parse_qs(parsed.query).get("atom", [""])[0]
            try:
                payload = sprites.png(atom)
            except (ValueError, OSError, KeyError):
                payload = None
            if payload is None:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "public, max-age=3600")
            self.end_headers()
            self.wfile.write(payload)
            return
        if path not in ("/", "/index.html", "/app.js", "/gpu.js", "/mapcore-client.js", "/style.css"):
            self.send_error(404)
            return
        asset = HERE / ("index.html" if path == "/" else path.lstrip("/"))
        payload = asset.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", mimetypes.guess_type(asset)[0] or "text/plain")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


if __name__ == "__main__":
    host, port = "127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    print(f"Map Studio: http://{host}:{port}", flush=True)
    ThreadingHTTPServer((host, port), Handler).serve_forever()
