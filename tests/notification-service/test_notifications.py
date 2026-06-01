from __future__ import annotations

from pathlib import Path
import io
import json
import sys
import unittest

SERVICE_DIR = Path(__file__).resolve().parents[2] / "services" / "notification-service"
sys.path.append(str(SERVICE_DIR))

from notifier import ConsoleChannel, IncidentAlert, Notifier
from worker import NotificationWorker


class NotificationServiceTests(unittest.TestCase):
    def test_high_severity_incident_gets_urgent_priority(self) -> None:
        alert = IncidentAlert.from_incident(
            {"id": "INC-1", "title": "Crash", "severity": "high", "location": "I-95"}
        )

        self.assertEqual(alert.priority, "URGENT")
        self.assertIn("URGENT DISPATCH ALERT", alert.subject)

    def test_notifier_sends_log_email_and_sms_records(self) -> None:
        stream = io.StringIO()
        notifier = Notifier(
            dispatcher={"name": "Dispatch", "email": "dispatch@city.test", "phone": "+15550001"},
            channels=[
                ConsoleChannel("log", "name", stream),
                ConsoleChannel("email", "email", stream),
                ConsoleChannel("sms", "phone", stream),
            ],
        )

        records = notifier.notify_incident_created(
            {"id": "INC-2", "title": "Flood", "severity": "medium", "location": "River Rd"}
        )

        self.assertEqual([record.channel for record in records], ["log", "email", "sms"])
        self.assertTrue(all(record.status == "sent" for record in records))
        printed = [json.loads(line) for line in stream.getvalue().splitlines()]
        self.assertEqual(len(printed), 3)
        self.assertEqual({item["priority"] for item in printed}, {"NORMAL"})

    def test_worker_processes_incident_created_event(self) -> None:
        stream = io.StringIO()
        notifier = Notifier(channels=[ConsoleChannel("log", "name", stream)])
        worker = NotificationWorker(notifier=notifier)
        worker.start()
        try:
            incident_id = worker.publish_incident_created(
                {"title": "Fire", "severity": "critical", "location": "Warehouse 4"}
            )
            worker.wait_until_idle()
        finally:
            worker.stop()

        self.assertTrue(incident_id.startswith("INC-"))
        self.assertEqual(len(worker.deliveries), 1)
        self.assertEqual(worker.deliveries[0].priority, "URGENT")
        self.assertIn("incident_notification_sent", stream.getvalue())


if __name__ == "__main__":
    unittest.main()
