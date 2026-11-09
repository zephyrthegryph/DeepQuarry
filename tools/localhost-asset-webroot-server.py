#!/usr/bin/env python3
import gzip
import io
import mimetypes
import os
import re
import socket
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from functools import lru_cache

ROOT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), '..', 'data', 'asset-store')
)
DEFAULT_PORT = 18715  # outside Windows' dynamic range (49152-65535), where WinNAT reserves blocks at will
BIND_FAILED = 3  # exit code the server watcher in tools/build/build.ts reads


def configured_port():
    # One source: the port of ASSET_CDN_URL in the server's resources.txt.
    config = os.path.join(
        os.path.dirname(__file__), '..',
        os.environ.get('DQ_SERVER_CONFIG_DIR') or 'config/example', 'resources.txt',
    )
    try:
        with open(config) as f:
            for line in f:
                m = re.match(r'\s*ASSET_CDN_URL\s+https?://[^/:\s]+:(\d+)', line)
                if m:
                    return int(m.group(1))
    except OSError:
        pass
    return DEFAULT_PORT


COMPRESSIBLE_EXTENSIONS = {
    '.css', '.html', '.js', '.json', '.map', '.svg', '.txt', '.xml',
}


@lru_cache(maxsize=1024)
def compressed_file(path, modified, size):
    del modified, size
    with open(path, 'rb') as source:
        return gzip.compress(source.read(), compresslevel=6, mtime=0)


class AssetHTTPServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def get_request(self):
        request, address = super().get_request()
        request.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        return request, address


class CORSRequestHandler(SimpleHTTPRequestHandler):
    # The old helper inherited HTTP/1.0, forcing a fresh TCP connection for every
    # code-split UI chunk. Persistent HTTP/1.1 matches production webroot hosting.
    protocol_version = 'HTTP/1.1'

    def log_request(self, code='-', size='-'):
        # Every chunk is a request; the log (build.ts ServerTarget) keeps errors only.
        pass

    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS')
        self.send_header('Timing-Allow-Origin', '*')
        self.send_header('Cache-Control', 'public, max-age=31536000, immutable')
        return super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header('Content-Length', '0')
        self.end_headers()

    def send_head(self):
        path = self.translate_path(self.path)
        accepts_gzip = 'gzip' in self.headers.get('Accept-Encoding', '').lower()
        extension = os.path.splitext(path)[1].lower()
        if (
            accepts_gzip
            and extension in COMPRESSIBLE_EXTENSIONS
            and os.path.isfile(path)
        ):
            stat = os.stat(path)
            compressed = compressed_file(path, stat.st_mtime_ns, stat.st_size)
            self.send_response(200)
            self.send_header(
                'Content-Type',
                mimetypes.guess_type(path)[0] or 'application/octet-stream',
            )
            self.send_header('Content-Encoding', 'gzip')
            self.send_header('Vary', 'Accept-Encoding')
            self.send_header('Content-Length', str(len(compressed)))
            self.send_header(
                'Last-Modified', self.date_time_string(stat.st_mtime)
            )
            self.end_headers()
            return io.BytesIO(compressed)
        return super().send_head()


os.makedirs(ROOT, exist_ok=True)
os.chdir(ROOT)
PORT = configured_port()
try:
    httpd = AssetHTTPServer(('127.0.0.1', PORT), CORSRequestHandler)
except OSError as error:
    print(f'asset webroot: cannot bind 127.0.0.1:{PORT}: {error}', flush=True)
    sys.exit(BIND_FAILED)
try:
    httpd.serve_forever()
except KeyboardInterrupt:
    pass
finally:
    httpd.server_close()
