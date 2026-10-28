"""Запуск локального интерфейса и Python API."""

import argparse

from backend.server import serve


def main() -> None:
    parser = argparse.ArgumentParser(description="Локальный сайт Барометр")
    parser.add_argument("--port", type=int, default=8000, help="порт (по умолчанию 8000)")
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("порт должен быть от 1 до 65535")
    serve(args.port)


if __name__ == "__main__":
    main()
