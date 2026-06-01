
# The http server that receives reports and runs ...
# the classifiers and then forwards structured...
# i ncidents downstream to the incident-service
import httpx
import os
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv

from .hotline import HotlineReport, IncidentCreate, process_hotline_report

# Load environment variables
load_dotenv()

# --- FastAPI App Initialization ---
app = FastAPI(
    title="Emergency Hotline Service",
    description="Simulated hotline service to process reports and create incidents.",
    version="1.0.0",
)

# --- CORS Middleware ---
# This is crucial for frontend applications (like the PWA or Flutter app) to communicate
# with this backend service. Adjust `allow_origins` for production.
origins = [
    "http://localhost",
    "http://localhost:3000", # Example for a React/Next.js frontend
    "http://localhost:8080", # Example for another local dev server
    os.getenv("FRONTEND_URL", "*"), # Allow frontend URL from environment variable
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Configuration ---
# The API Gateway will route to the incident-service. This service needs to know the
# internal URL of the API Gateway or the incident-service directly.
# For hackathon, assume API_GATEWAY_URL is set.
API_GATEWAY_URL = os.getenv("API_GATEWAY_URL", "http://localhost:8000") # Default for local testing
INCIDENT_SERVICE_ENDPOINT = f"{API_GATEWAY_URL}/incidents" # Assuming API Gateway exposes /incidents

# --- API Endpoint ---

@app.post("/hotline/report", response_model=IncidentCreate, status_code=201)
async def report_incident_via_hotline(report: HotlineReport):
    """
    Receives a simulated hotline report, processes it, and forwards it to the incident-service.
    """
    try:
        # 1. Process the hotline report using the logic from hotline.py
        incident_data = process_hotline_report(report)
        
        # 2. Forward the processed incident data to the incident-service via API Gateway
        async with httpx.AsyncClient() as client:
            response = await client.post(INCIDENT_SERVICE_ENDPOINT, json=incident_data.model_dump())
            response.raise_for_status() # Raise an exception for bad status codes (4xx or 5xx)
            
            # Assuming incident-service returns the created incident, parse it
            created_incident = IncidentCreate(**response.json())
            return created_incident
            
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=e.response.status_code, detail=f"Incident service error: {e.response.text}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

# --- Health Check (Optional but Recommended) ---
@app.get("/health")
async def health_check():
    return {"status": "ok", "service": "hotline-service"}
