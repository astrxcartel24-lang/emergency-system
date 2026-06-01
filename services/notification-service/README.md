# Notification Service

Mock real-time alert system for Member 6. The service accepts incident-created
events, queues them for a background worker, and simulates dispatcher delivery
through log, email, and SMS channels.

## Features

- `POST /incidents` queues a new incident-created event.
- Background worker immediately processes queued incidents.
- Mock log, email, and SMS channels print structured JSON delivery records.
- High, critical, urgent, and severe incidents are marked as `URGENT` priority.
- `GET /health` reports worker queue depth and delivery count.

## Run locally

```bash
python services/notification-service/worker.py --port 8090
```

## Publish a demo incident

```bash
curl -X POST http://localhost:8090/incidents \
  -H 'Content-Type: application/json' \
  -d '{"id":"INC-100","title":"Building fire","severity":"high","location":"7th Ave","reporter":"hotline"}'
```

The worker prints one JSON record per mock channel, including `priority`,
`incident_id`, `channel`, and dispatcher destination.
