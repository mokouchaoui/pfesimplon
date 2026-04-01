import os
import uuid
from datetime import datetime, timezone

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from flask import Flask, jsonify, request
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

# Minimal in-memory storage for demo purposes.
TICKETS = []


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/tickets")
def list_tickets():
    return jsonify(TICKETS)


@app.post("/tickets")
def create_ticket():
    body = request.get_json(silent=True) or {}
    title = (body.get("title") or "").strip()
    description = (body.get("description") or "").strip()

    if not title:
        return jsonify({"error": "title is required"}), 400

    ticket = {
        "id": str(uuid.uuid4()),
        "title": title,
        "description": description,
        "status": "open",
        "createdAt": datetime.now(timezone.utc).isoformat(),
    }
    TICKETS.append(ticket)

    # Optional async event to SQS for background processing.
    queue_url = os.getenv("SQS_QUEUE_URL", "")
    if queue_url:
        try:
            sqs = boto3.client("sqs", region_name=os.getenv("AWS_REGION", "us-east-1"))
            sqs.send_message(QueueUrl=queue_url, MessageBody=ticket["id"])
        except (BotoCoreError, ClientError):
            pass

    return jsonify(ticket), 201


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")))
