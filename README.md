# Emergency Hotline Service

Small FastAPI microservice that processes hotline reports and forwards structured incidents to an incident service.

## Overview

- Receives raw hotline reports (speech-to-text or dispatcher input).
- Runs a small classifier (`process_hotline_report`) to produce an `IncidentCreate` payload.
- Forwards the structured incident to an `INCIDENT_SERVICE_ENDPOINT` (configured via `API_GATEWAY_URL`).

## Files

- [hotline.py](hotline.py): Pydantic models and report processing logic.
- [app.py](app.py): FastAPI app with `/hotline/report` POST and `/health` GET.

## Prerequisites

- Python 3.10+ recommended
- Virtual environment (optional but recommended)

## Install

```bash
python -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install fastapi uvicorn httpx python-dotenv pydantic
```

## Run (two options)

From the `firefix` package folder (preferred if you run the package as-is):

```bash
cd /home/gift/Downloads/Build54hackathon/firefix
uvicorn Service.app:app --reload --port 8000 --log-level debug
```

Or from the repository root with `PYTHONPATH` set:

```bash
cd /home/gift/Downloads/Build54hackathon
PYTHONPATH=. uvicorn firefix.Service.app:app --reload --port 8000 --log-level debug
```

## Environment variables

- `API_GATEWAY_URL` — base URL to forward incidents to (default: `http://localhost:8000`).
  - The service will POST to `${API_GATEWAY_URL}/incidents`.
- `FRONTEND_URL` — used for CORS allow_origins (default: `*` in development).

Example (set a fake incident service to avoid forwarding errors while testing):

```bash
API_GATEWAY_URL=http://localhost:9000 PYTHONPATH=. uvicorn firefix.Service.app:app --port 8000
```

## Endpoints

- `GET /health` — quick health check. Returns `{"status":"ok","service":"hotline-service"}`.
- `POST /hotline/report` — accepts JSON matching `HotlineReport` and returns an `IncidentCreate`.

Sample POST payload:

```json
{
  "caller_id": "anonymous",
  "transcribed_text": "There is a fire at Main St",
  "location_hint": "Main St"
}
```

Curl example:

```bash
curl -s -X POST http://127.0.0.1:8000/hotline/report \
  -H "Content-Type: application/json" \
  -d '{"caller_id":"anonymous","transcribed_text":"There is a fire at Main St","location_hint":"Main St"}'
```

## Troubleshooting

- "Could not connect" to port 8000: server not started. Start uvicorn using one of the Run commands above and re-check with `curl /health`.
- Import errors from `from .hotline import ...`: ensure you run uvicorn with the package path (`cd firefix && uvicorn Service.app:app`) or set `PYTHONPATH=.` when running from repo root. Adding minimal `__init__.py` files in `firefix/` and `firefix/Service/` also makes them proper packages.
- Forwarding failures (4xx/5xx): `API_GATEWAY_URL` likely points to an endpoint that is down or returning errors. For local testing, point it at a mock server or a different port.
- If the POST to `/hotline/report` fails because the incident service is unreachable, set `API_GATEWAY_URL` to a test endpoint or run a simple mock server:

```bash
# Quick mock using Python's http.server (responds 200 but doesn't validate body)
python -m http.server 9000
```

## Next steps

- Add simple integration tests or a mock incident-service to validate forwarding.
- Optionally add `__init__.py` files to `firefix/` and `firefix/Service/` to avoid package import issues.

---
If you want, I can also add the `__init__.py` files or a minimal `requirements.txt` and run the health + example POST for you.
