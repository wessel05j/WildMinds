from __future__ import annotations

import argparse
import json
import os
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

from .brain import AIAction, HeuristicMind, LocalCreatureMind, bootstrap_local_model, creature_from_payload


class WildMindsAIService:
    def __init__(self, force_heuristic: bool = False) -> None:
        bootstrap = bootstrap_local_model(force_heuristic=force_heuristic)
        self.bootstrap = bootstrap
        if bootstrap.ready:
            self.mind = LocalCreatureMind(model_name=bootstrap.model_choice.model_name)
        else:
            self.mind = HeuristicMind()

    def status_payload(self) -> dict[str, Any]:
        return {
            "ready": True,
            "using_local_ai": self.bootstrap.ready,
            "model_name": self.bootstrap.model_choice.model_name,
            "details": self.bootstrap.details,
        }

    def decide(self, payload: dict[str, Any]) -> AIAction:
        creature = creature_from_payload(payload.get("creature", {}))
        snapshot = payload.get("snapshot", {})
        return self.mind.decide(creature, snapshot)


class RequestHandler(BaseHTTPRequestHandler):
    service: WildMindsAIService

    def log_message(self, format: str, *args: object) -> None:
        return

    def do_GET(self) -> None:
        if self.path != "/health":
            self._write_json({"error": "not found"}, status=HTTPStatus.NOT_FOUND)
            return
        self._write_json(self.service.status_payload())

    def do_POST(self) -> None:
        if self.path != "/decide":
            self._write_json({"error": "not found"}, status=HTTPStatus.NOT_FOUND)
            return

        content_length = int(self.headers.get("Content-Length", "0") or 0)
        try:
            payload = json.loads(self.rfile.read(content_length).decode("utf-8"))
        except json.JSONDecodeError:
            self._write_json({"error": "invalid json"}, status=HTTPStatus.BAD_REQUEST)
            return

        action = self.service.decide(payload)
        self._write_json(action.as_dict())

    def _write_json(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status.value)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="WildMinds AI helper service")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--force-heuristic", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    force_heuristic = args.force_heuristic or os.getenv("WILDMINDS_FORCE_HEURISTIC") == "1"
    RequestHandler.service = WildMindsAIService(force_heuristic=force_heuristic)
    server = ThreadingHTTPServer((args.host, args.port), RequestHandler)
    print(f"WildMinds AI helper listening on http://{args.host}:{args.port}")
    print(json.dumps(RequestHandler.service.status_payload()))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
