"""Serve only a specified model file over localhost for adb reverse test setup."""
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import shutil
import sys

model = Path(sys.argv[1]).resolve(strict=True)


class ModelHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/model.gguf':
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header('Content-Length', str(model.stat().st_size))
        self.send_header('Content-Type', 'application/octet-stream')
        self.end_headers()
        with model.open('rb') as source:
            shutil.copyfileobj(source, self.wfile, length=256 * 1024)


print('Serving the test model on localhost:8765 only.', flush=True)
HTTPServer(('127.0.0.1', 8765), ModelHandler).serve_forever()
