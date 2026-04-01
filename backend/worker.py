import os
import time

import boto3
from botocore.exceptions import BotoCoreError, ClientError


def main() -> None:
    queue_url = os.getenv("SQS_QUEUE_URL", "")
    region = os.getenv("AWS_REGION", "us-east-1")

    if not queue_url:
        print("SQS_QUEUE_URL is empty; worker idle")
        while True:
            time.sleep(60)

    sqs = boto3.client("sqs", region_name=region)
    print("worker started")

    while True:
        try:
            resp = sqs.receive_message(
                QueueUrl=queue_url,
                MaxNumberOfMessages=10,
                WaitTimeSeconds=20,
            )
            for msg in resp.get("Messages", []):
                receipt = msg["ReceiptHandle"]
                body = msg.get("Body", "")
                print(f"processed ticket event: {body}")
                sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=receipt)
        except (BotoCoreError, ClientError) as exc:
            print(f"worker error: {exc}")
            time.sleep(5)


if __name__ == "__main__":
    main()
