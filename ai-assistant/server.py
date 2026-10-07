"""Small web server for the DRIVER AI assistant (http://localhost:8800).

Only listens on this computer (127.0.0.1). Endpoints:
    GET  /                  the assistant page
    POST /api/ask           {"question": "...", "history": [{"question", "plans"}]} -> answers
    POST /api/export        {"plan": {...}, "format": "csv"|"xlsx"} -> file
    POST /api/refresh       reload fields and values after the form or data changed
    GET  /api/health        status
"""
import json
import os
import threading
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import driver_ai

HERE = os.path.dirname(os.path.abspath(__file__))
ALLOWED_ORIGINS = {"http://localhost:7000", "http://127.0.0.1:7000"}


def serve(assistant, port):
    lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        server_version = "DriverAI/1.0"

        def log_message(self, fmt, *args):
            pass

        def cors(self):
            origin = self.headers.get("Origin")
            if origin in ALLOWED_ORIGINS:
                self.send_header("Access-Control-Allow-Origin", origin)
                self.send_header("Access-Control-Allow-Headers", "Content-Type")
                self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
                self.send_header("Access-Control-Expose-Headers", "Content-Disposition")

        def reply(self, code, body, ctype="application/json", filename=None):
            if not isinstance(body, bytes):
                body = json.dumps(body, ensure_ascii=False, default=str).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            if filename:
                self.send_header("Content-Disposition", 'attachment; filename="%s"' % filename)
            self.cors()
            self.end_headers()
            self.wfile.write(body)

        def read_json(self):
            n = int(self.headers.get("Content-Length") or 0)
            if n > 300000:
                raise ValueError("request too large")
            return json.loads(self.rfile.read(n).decode("utf-8") or "{}")

        def do_OPTIONS(self):
            self.send_response(204)
            self.cors()
            self.end_headers()

        def do_GET(self):
            path = self.path.split("?")[0]
            if path in ("/", "/index.html"):
                with open(os.path.join(HERE, "web", "index.html"), "rb") as f:
                    self.reply(200, f.read(), "text/html; charset=utf-8")
            elif path == "/api/health":
                self.reply(200, {"ok": True, "model": driver_ai.MODEL, "tables": list(assistant.d.tables)})
            else:
                self.reply(404, {"ok": False, "error": "not found"})

        def do_POST(self):
            path = self.path.split("?")[0]
            try:
                body = self.read_json()
                if path == "/api/ask":
                    question = str(body.get("question") or "").strip()[:500]
                    if not question:
                        return self.reply(400, {"ok": False, "error": "Please type a question."})
                    history = body.get("history") if isinstance(body.get("history"), list) else []
                    with lock:     # one question at a time; a small model is busy enough
                        res = assistant.ask(question, history=history)
                    self.reply(200, res)
                elif path == "/api/export":
                    fmt = "xlsx" if body.get("format") == "xlsx" else "csv"
                    plan = body.get("plan") or {}
                    plan["_question"] = str(body.get("question") or "")[:500]
                    data, name, ctype = assistant.export(plan, fmt)
                    self.reply(200, data, ctype, filename=name)
                elif path == "/api/refresh":
                    with lock:
                        assistant.refresh()
                    self.reply(200, {"ok": True, "tables": list(assistant.d.tables)})
                else:
                    self.reply(404, {"ok": False, "error": "not found"})
            except driver_ai.PlanError as e:
                self.reply(400, {"ok": False, "error": str(e)})
            except Exception as e:   # keep the server running
                traceback.print_exc()
                self.reply(500, {"ok": False, "error": "Internal error: %s" % e})

    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print("DRIVER AI assistant: http://localhost:%d  (model %s, Ctrl+C to stop)" % (port, driver_ai.MODEL))
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
