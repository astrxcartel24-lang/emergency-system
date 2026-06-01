"""Mock dispatcher notification channels for incident alerts.

The module is intentionally dependency-free so the worker can run in local demos,
containers, or CI without external SMS/email providers. Each channel writes a
structured message to stdout and returns a delivery record that tests or future
integrations can inspect.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any, Protocol
import json
import sys
import uuid


HIGH_SEVERITIES = {"high", "critical", "urgent", "severe"}
DEFAULT_DISPATCHER = {
    "name": "Primary Dispatcher",
    "email": "dispatcher@example.com",
    "phone": "+15550101199",
}


@dataclass(frozen=True)
class IncidentAlert:
    """Normalized incident payload used by notification channels."""

    incident_id: str
    title: str
    severity: str
    location: str
    description: str = ""
    reporter: str = "unknown"
    created_at: str = field(default_factory=lambda: datetime.now(UTC).isoformat())

    @classmethod
    def from_incident(cls, incident: dict[str, Any]) -> "IncidentAlert":
        """Create a normalized alert from an incident-created event."""

        incident_id = str(incident.get("id") or incident.get("incident_id") or uuid.uuid4())
        title = str(incident.get("title") or incident.get("type") or "New incident")
        severity = str(incident.get("severity") or "medium").lower()
        location_value = incident.get("location") or incident.get("address") or "unknown location"
        if isinstance(location_value, dict):
            location = ", ".join(str(value) for value in location_value.values() if value)
        else:
            location = str(location_value)

        return cls(
            incident_id=incident_id,
            title=title,
            severity=severity,
            location=location or "unknown location",
            description=str(incident.get("description") or incident.get("details") or ""),
            reporter=str(incident.get("reporter") or incident.get("reported_by") or "unknown"),
            created_at=str(incident.get("created_at") or datetime.now(UTC).isoformat()),
        )

    @property
    def priority(self) -> str:
        """Return URGENT for high-severity incidents and NORMAL otherwise."""

        return "URGENT" if self.severity in HIGH_SEVERITIES else "NORMAL"

    @property
    def subject(self) -> str:
        """Human-readable dispatcher alert subject."""

        prefix = "URGENT DISPATCH ALERT" if self.priority == "URGENT" else "Dispatch alert"
        return f"{prefix}: {self.title} ({self.severity})"

    def message(self) -> str:
        """Format a concise SMS/email body for the dispatcher."""

        lines = [
            self.subject,
            f"Incident ID: {self.incident_id}",
            f"Location: {self.location}",
            f"Reporter: {self.reporter}",
            f"Created: {self.created_at}",
        ]
        if self.description:
            lines.append(f"Details: {self.description}")
        return "\n".join(lines)


@dataclass(frozen=True)
class DeliveryRecord:
    """Result of a mock notification send."""

    channel: str
    destination: str
    status: str
    priority: str
    incident_id: str
    sent_at: str = field(default_factory=lambda: datetime.now(UTC).isoformat())


class NotificationChannel(Protocol):
    """Protocol for pluggable notification channels."""

    name: str

    def send(self, alert: IncidentAlert, dispatcher: dict[str, str]) -> DeliveryRecord:
        """Send an alert and return a delivery record."""


class ConsoleChannel:
    """Mock channel that emits structured notifications to stdout."""

    def __init__(self, name: str, destination_key: str, stream: Any = None) -> None:
        self.name = name
        self.destination_key = destination_key
        self.stream = stream or sys.stdout

    def send(self, alert: IncidentAlert, dispatcher: dict[str, str]) -> DeliveryRecord:
        destination = dispatcher.get(self.destination_key, "dispatcher")
        payload = {
            "event": "incident_notification_sent",
            "channel": self.name,
            "destination": destination,
            "priority": alert.priority,
            "incident_id": alert.incident_id,
            "subject": alert.subject,
            "message": alert.message(),
        }
        print(json.dumps(payload, sort_keys=True), file=self.stream, flush=True)
        return DeliveryRecord(
            channel=self.name,
            destination=destination,
            status="sent",
            priority=alert.priority,
            incident_id=alert.incident_id,
        )


class Notifier:
    """Send incident-created alerts to the dispatcher over mock channels."""

    def __init__(
        self,
        dispatcher: dict[str, str] | None = None,
        channels: list[NotificationChannel] | None = None,
    ) -> None:
        self.dispatcher = dispatcher or DEFAULT_DISPATCHER
        self.channels = channels or [
            ConsoleChannel("log", "name"),
            ConsoleChannel("email", "email"),
            ConsoleChannel("sms", "phone"),
        ]

    def notify_incident_created(self, incident: dict[str, Any]) -> list[DeliveryRecord]:
        """Send an alert for a newly created incident."""

        alert = IncidentAlert.from_incident(incident)
        return [channel.send(alert, self.dispatcher) for channel in self.channels]
