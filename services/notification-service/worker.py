"""Background worker and demo HTTP entry point for incident notifications.

Run locally:
    python services/notification-service/worker.py

Then publish an incident-created event:
    curl -X POST http://localhost:8090/incidents \
      -H 'Content-Type: application/json' \
      -d '{"id":"INC-1","title":"Road accident","severity":"high","location":"Main St"}'
"""

from __future__ import annotations

from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from queue import Empty, Queue
from threading import Event, Thread
from typing import Any
import argparse
import json
import sys
import time

if __package__ in {None, ""}:
    sys.path.append(str(Path(__file__).resolve().parent))

from notifier import DeliveryRecord, Notifier


class NotificationWorker:
    """Queue-backed background worker for real-time incident alerts."""

    def __init__(self, notifier: Notifier | None = None) -> None:
        self.notifier = notifier or Notifier()
        self.queue: Queue[dict[str, Any]] = Queue()
        self.stop_event = Event()
        self.thread: Thread | None = None
        self.deliveries: list[DeliveryRecord] = []

    def start(self) -> None:
        """Start processing queued incident-created events."""

        if self.thread and self.thread.is_alive():
            return
        self.thread = Thread(target=self._run, name="notification-worker", daemon=True)
        self.thread.start()

    def stop(self, timeout: float = 5.0) -> None:
        """Stop the worker after processing any active item."""

        self.stop_event.set()
        if self.thread:
            self.thread.join(timeout=timeout)

    def publish_incident_created(self, incident: dict[str, Any]) -> str:
        """Queue an incident-created event and return its normalized id."""

        incident_id = str(incident.get("id") or incident.get("incident_id") or f"INC-{int(time.time() * 1000)}")
        event = {**incident, "id": incident_id, "event": "incident.created"}
        self.queue.put(event)
        return incident_id

    def wait_until_idle(self) -> None:
        """Block until all currently queued events have been processed."""

        self.queue.join()

    def _run(self) -> None:
        while not self.stop_event.is_set():
            try:
                event = self.queue.get(timeout=0.2)
            except Empty:
                continue

            try:
                records = self.notifier.notify_incident_created(event)
                self.deliveries.extend(records)
            finally:
                self.queue.task_done()


def build_handler(worker: NotificationWorker) -> type[BaseHTTPRequestHandler]:
    """Build an HTTP handler bound to a worker instance."""

    class NotificationRequestHandler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            if self.path != "/health":
                self._send_json({"error": "not found"}, HTTPStatus.NOT_FOUND)
                return
            self._send_json(
                {
                    "status": "ok",
                    "queued": worker.queue.qsize(),
                    "deliveries": len(worker.deliveries),
                }
            )

        def do_POST(self) -> None:
            if self.path != "/incidents":
                self._send_json({"error": "not found"}, HTTPStatus.NOT_FOUND)
                return

            body = self.rfile.read(int(self.headers.get("Content-Length", "0") or "0"))
            try:
                payload = json.loads(body or b"{}")
            except json.JSONDecodeError:
                self._send_json({"error": "invalid JSON body"}, HTTPStatus.BAD_REQUEST)
                return

            if not isinstance(payload, dict):
                self._send_json({"error": "incident body must be an object"}, HTTPStatus.BAD_REQUEST)
                return

            incident_id = worker.publish_incident_created(payload)
            self._send_json(
                {"status": "queued", "incident_id": incident_id, "queued": worker.queue.qsize()},
                HTTPStatus.ACCEPTED,
            )

        def log_message(self, format: str, *args: Any) -> None:
            print(f"notification-service {self.address_string()} - {format % args}", file=sys.stderr)

        def _send_json(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
            body = json.dumps(payload).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    return NotificationRequestHandler


def run_server(host: str, port: int) -> None:
    """Run the notification HTTP service."""

    worker = NotificationWorker()
    worker.start()
    server = ThreadingHTTPServer((host, port), build_handler(worker))
    print(f"notification-service listening on http://{host}:{port}", flush=True)
    try:
        server.serve_forever()
    finally:
        server.server_close()
        worker.stop()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Mock emergency incident notification worker")
    parser.add_argument("--host", default="0.0.0.0", help="HTTP host to bind")
    parser.add_argument("--port", default=8090, type=int, help="HTTP port to bind")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    run_server(args.host, args.port)
