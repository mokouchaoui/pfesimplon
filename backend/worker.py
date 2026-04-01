# =============================================================================
# backend/worker.py
# -----------------------------------------------------------------------------
# The SQS consumer worker — the other half of the producer/consumer pattern.
# Runs as a separate Kubernetes Deployment (1 replica) using the same Docker
# image as the backend, but with a different CMD: "python worker.py".
# Continuously polls the SQS queue for new ticket events and processes them.
# =============================================================================

import os
import time

import boto3  # AWS SDK — used to receive and delete SQS messages
from botocore.exceptions import BotoCoreError, ClientError


def main() -> None:
    # Read configuration from environment variables.
    # These are injected by Kubernetes from the ConfigMap and Secret.
    queue_url = os.getenv("SQS_QUEUE_URL", "")
    region = os.getenv("AWS_REGION", "us-east-1")

    # If no queue URL is configured, run in idle mode.
    # This prevents the container from crash-looping on misconfiguration.
    if not queue_url:
        print("SQS_QUEUE_URL is empty; worker idle")
        while True:
            time.sleep(60)

    sqs = boto3.client("sqs", region_name=region)
    print("worker started")  # This log line appears in CloudWatch on pod startup

    # ---------------------------------------------------------------------------
    # Main polling loop — runs forever until the pod is stopped.
    # Uses SQS long polling (WaitTimeSeconds=20) which means:
    #   - The API call blocks for up to 20 seconds waiting for messages
    #   - Much cheaper than polling every second (reduces API calls by ~95%)
    #   - Reduces latency compared to short polling
    # ---------------------------------------------------------------------------
    while True:
        try:
            resp = sqs.receive_message(
                QueueUrl=queue_url,
                MaxNumberOfMessages=10,   # Process up to 10 messages per batch
                WaitTimeSeconds=20,       # Long polling — wait up to 20s for messages
            )
            for msg in resp.get("Messages", []):
                receipt = msg["ReceiptHandle"]  # Token needed to delete the message
                body = msg.get("Body", "")      # Contains the ticket ID sent by app.py

                # -----------------------------------------------------------------
                # Process the ticket event.
                # In this demo: just log it. In production this could:
                #   - Send an email notification
                #   - Update a database record
                #   - Trigger downstream services
                # -----------------------------------------------------------------
                print(f"processed ticket event: {body}")

                # Delete the message from the queue AFTER successful processing.
                # If we crash before this line, SQS will make the message visible
                # again after the visibility timeout, and we'll retry it.
                # After 5 failures (maxReceiveCount), it goes to the DLQ.
                sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=receipt)

        except (BotoCoreError, ClientError) as exc:
            # Log the error and wait before retrying.
            # Prevents a tight crash loop if AWS is temporarily unreachable.
            print(f"worker error: {exc}")
            time.sleep(5)


if __name__ == "__main__":
    main()
