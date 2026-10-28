"""Локальный HTTP-сервер для интерфейса и API на одном адресе."""

from __future__ import annotations

import json
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

from .calculations import compare_pressure, height_from_measurements, pressure_table

FRONTEND_DIR = Path(__file__).resolve().parent.parent / "frontend"
ROUTES = {
    "/api/table": pressure_table,
    "/api/height": height_from_measurements,
    "/api/compare": compare_pressure,
}


class Handler(SimpleHTTPRequestHandler):
    def _json(self, status: int, payload: dict) -> None:
        encoded = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self) -> None:
        if urlsplit(self.path).path == "/api/health":
            self._json(200, {"status": "ok"})
            return
        super().do_GET()

    def do_POST(self) -> None:
        route = ROUTES.get(urlsplit(self.path).path)
        if route is None:
            self._json(404, {"error": "Маршрут API не найден."})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 65536:
                raise ValueError("Размер запроса должен быть от 1 до 65536 байт.")
            data = json.loads(self.rfile.read(length))
            if not isinstance(data, dict):
                raise ValueError("Ожидается объект JSON.")
            result = route(data)
        except (ValueError, json.JSONDecodeError) as exc:
            self._json(400, {"error": str(exc)})
            return
        self._json(200, result)


def serve(port: int = 8000) -> None:
    handler = partial(Handler, directory=str(FRONTEND_DIR))
    with ThreadingHTTPServer(("127.0.0.1", port), handler) as server:
        print(f"Сайт открыт по адресу http://localhost:{port}", flush=True)
        print("Для остановки нажмите Ctrl+C.", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\nСервер остановлен.")
