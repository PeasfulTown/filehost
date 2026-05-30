import json
import urllib.parse
import boto3
import os
from datetime import datetime

s3 = boto3.client("s3")
dynamodb = boto3.client("dynamodb")

# The exact table name will be supplied dynamically by Terraform
TABLE_NAME = os.environ.get("TABLE_NAME", "FileMetadata")
table = dynamodb.Table(TABLE_NAME)


def lambda_handler(event, context):
    # 1. Parse the bucket name and file name from the incoming S3 event payload
    bucket = event["Records"][0]["s3"]["bucket"]["name"]
    key = urllib.parse.unquote_plus(
        event["Records"][0]["s3"]["object"]["key"], encoding="utf-8"
    )

    try:
        # 2. Query S3 for the file's system properties (Size, Content Type)
        response = s3.head_object(Bucket=bucket, Key=key)

        # 3. Format the data neatly for our Database
        metadata = {
            "FileName": key,
            "Timestamp": datetime.utcnow().isoformat(),
            "FileSize": response["ContentLength"],
            "ContentType": response["ContentType"],
        }

        # 4. Save directly into DynamoDB
        table.put_item(Item=metadata)

        return {
            "statusCode": 200,
            "body": json.dumps("Metadata successfully extracted and logged!"),
        }
    except Exception as e:
        print(f"Error processing metadata for file {key}: {str(e)}")
        raise e
