"""Run the static site locally with Python's standard library."""

from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from functools import partial


def main() -> None:
    site_dir = Path(__file__).resolve().parent / "dist"
    handler = partial(SimpleHTTPRequestHandler, directory=str(site_dir))
    with ThreadingHTTPServer(("127.0.0.1", 8000), handler) as server:
        print("Сайт открыт по адресу http://localhost:8000", flush=True)
        print("Для остановки нажмите Ctrl+C.", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\nСервер остановлен.")


if __name__ == "__main__":
    main()
