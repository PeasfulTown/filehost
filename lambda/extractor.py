import json
import urllib.parse
import boto3
import os
from mimetypes import guess_type

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")

# The exact table name will be supplied dynamically by Terraform
TABLE_NAME = os.environ.get("TABLE_NAME", "FileMetadata")
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    bucket = event["Records"][0]["s3"]["bucket"]["name"]
    key = urllib.parse.unquote_plus(
        event["Records"][0]["s3"]["object"]["key"], encoding="utf-8"
    )

    try:
        response = s3.head_object(Bucket=bucket, Key=key)

        s3_content_type = response.get("ContentType", "binary/octet-stream")

        if s3_content_type == "binary/octet-stream" or s3_content_type == "application/octet-stream":
            guessed_type, _ = guess_type(key)
            content_type = guessed_type if guessed_type else s3_content_type
        else:
            content_type = s3_content_type

        s3_last_modified = response["LastModified"].isoformat()

        metadata = {
            "FileName": key.split('/')[-1],
            "UploadedOn": s3_last_modified,
            "FileSizeInBytes": response["ContentLength"],
            "ContentType": content_type,
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
