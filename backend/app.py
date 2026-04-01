# =============================================================================
# backend/app.py
# -----------------------------------------------------------------------------
# The Flask REST API — the "brain" of the helpdesk application.
# Exposes 3 HTTP endpoints consumed by the Next.js frontend (via proxy).
# Also acts as the SQS producer: every new ticket triggers an async event.
# Runs on port 5000 inside the container, served by gunicorn in production.
# =============================================================================

import os
import uuid
from datetime import datetime, timezone

import boto3  # AWS SDK — used here to send messages to SQS
from botocore.exceptions import BotoCoreError, ClientError
from flask import Flask, jsonify, request
from flask_cors import CORS  # Allows cross-origin requests (needed for local dev)

app = Flask(__name__)
CORS(app)  # Enable CORS on all routes so browsers don't block requests

# ---------------------------------------------------------------------------
# In-memory ticket storage.
# Intentionally simple for the PFE demo — no database needed.
# Data lives only as long as the pod is running.
# In a real production system this would be replaced by DynamoDB or RDS.
# ---------------------------------------------------------------------------
TICKETS = []


@app.get("/health")
def health():
    # Kubernetes liveness/readiness probe hits this endpoint.
    # If it returns 200, the pod is considered healthy.
    # If it fails, Kubernetes restarts the pod automatically.
    return {"status": "ok"}


@app.get("/tickets")
def list_tickets():
    # Returns all tickets as a JSON array.
    # Called by the frontend on page load and after each ticket creation.
    return jsonify(TICKETS)


@app.post("/tickets")
def create_ticket():
    # Creates a new ticket from a JSON POST body: { title, description }
    body = request.get_json(silent=True) or {}
    title = (body.get("title") or "").strip()
    description = (body.get("description") or "").strip()

    # Validate that a title was provided — description is optional
    if not title:
        return jsonify({"error": "title is required"}), 400

    # Build the ticket object with a unique ID and UTC timestamp
    ticket = {
        "id": str(uuid.uuid4()),       # Universally unique identifier
        "title": title,
        "description": description,
        "status": "open",              # Default status for new tickets
        "createdAt": datetime.now(timezone.utc).isoformat(),
    }
    TICKETS.append(ticket)  # Save to in-memory list

    # ---------------------------------------------------------------------------
    # Async SQS event — producer side of the producer/consumer pattern.
    # Sends only the ticket ID (not the full object) to the queue.
    # The worker pod will pick this up and process it independently.
    # Wrapped in try/except so SQS failure never breaks ticket creation.
    # SQS_QUEUE_URL is injected from a Kubernetes Secret at runtime.
    # ---------------------------------------------------------------------------
    queue_url = os.getenv("SQS_QUEUE_URL", "")
    if queue_url:
        try:
            sqs = boto3.client("sqs", region_name=os.getenv("AWS_REGION", "us-east-1"))
            sqs.send_message(QueueUrl=queue_url, MessageBody=ticket["id"])
        except (BotoCoreError, ClientError):
            pass  # SQS failure is non-fatal — ticket is already saved

    return jsonify(ticket), 201  # 201 Created


if __name__ == "__main__":
    # Entry point for local development only.
    # In production (Docker/Kubernetes), gunicorn starts the app instead.
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")))
