from pydantic import BaseModel
from typing import Optional
import uuid
from datetime import datetime

# --- Pydantic Models ---

class HotlineReport(BaseModel):
    """Model for an incoming hotline report."""
    caller_id: str = "anonymous" # Can be phone number, or 'bystander', 'victim'
    transcribed_text: str
    # Location is embedded in text or derived by frontend
    # This comes from caller's device or dispatcher input
    location_hint: Optional[str] = None 
    timestamp: str = datetime.now().isoformat() # ISO format string

class IncidentCreate(BaseModel):
    """Model for creating a new incident in the incident-service."""
    id: str
    type: str # e.g., "Fire", "Medical", "Accident", "Other"
    description: str
    location: str
    urgency: str # e.g., "High", "Medium", "Low"
    status: str = "reported" # Initial status
    reported_at: str # ISO format
    source: str = "hotline"
    # Optional fields for intelligence layer
    is_duplicate: bool = False
    is_fraudulent: bool = False

# --- Report Processing Logic ---

def process_hotline_report(report: HotlineReport) -> IncidentCreate:
    """
    Processes a raw hotline report to extract incident details and prepare for incident creation.
    This is the 'intelligence layer' for the hackathon MVP.
    """
    incident_id = str(uuid.uuid4()) # Generate a unique ID for the incident
    description = report.transcribed_text
    incident_type = "Other"
    urgency = "Medium"
    location = report.location_hint if report.location_hint else "Unknown Location"

    
    # I will use a simple keyword matching for this part to classify the incidents based on priority
    text_lower = report.transcribed_text.lower()

    if "fire" in text_lower or "moto" in text_lower:
        incident_type = "Fire"
        urgency = "High"
    elif "accident" in text_lower or "ajali" in text_lower or "crash" in text_lower:
        incident_type = "Accident"
        urgency = "High"
    elif "medical" in text_lower or "mgonjwa" in text_lower or "emergency" in text_lower:
        incident_type = "Medical"
        urgency = "High"
    elif "theft" in text_lower or "wizi" in text_lower:
        incident_type = "Theft"
        urgency = "Medium"

    # This checks for any fraudulent or duplicate reports   
    is_duplicate = False # Placeholder
    is_fraudulent = False # Placeholder

    # I know that this is a simple MVP and for production we will use a more sophisticated NLP model
    # and a database to check for duplicates and a fraud detection model to detect fraudulent incidents

    return IncidentCreate(
        id=incident_id,
        type=incident_type,
        description=description,
        location=location,
        urgency=urgency,
        reported_at=report.timestamp,
        is_duplicate=is_duplicate,
        is_fraudulent=is_fraudulent
    )

