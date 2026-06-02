import os
import boto3
import ulid
from fastapi import FastAPI, UploadFile, File, HTTPException
from mangum import Mangum

app = FastAPI(title="FileHost Controller")

s3_client = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
BUCKET_NAME: str = os.environ["UPLOAD_BUCKET_NAME"]
TABLE_NAME: str = os.environ["METADATA_TABLE_NAME"]
table = dynamodb.Table(TABLE_NAME)

@app.get("/health")
def check_health():
    # TODO: implement actual health check endpoint
    return {"status": "healthy"}


@app.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    try:
        new_file_id = ulid.new()
        contents = await file.read()

        s3_client.put_object(
            Bucket=BUCKET_NAME,
            Key=f"uploads/{new_file_id}/{file.filename}",
            Body=contents
        )
        return {"message": "Success", "filename": file.filename}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"S3 storage error: {str(e)}")

@app.get("/files/{file_id}/info")
def get_file_information(file_id: str):
    """
    Retrieves metadata for a specific file based on its unique FileId
    """
    try:
        response = table.get_item(Key={"FileId": file_id})
        item = response.get("Item")
        if not item:
            raise HTTPException(
                    status_code=404,
                    detail=f"File with ID '{file_id}' does not exist."
                    )

        return item
    except HTTPException as e:
        raise e
    except Exception as e:
        print(f"Database error while fetching FileId {file_id}: {str(e)}")
        raise HTTPException(
                status_code=500,
                detail="An internal server error occurred while retrieving file information."
                )

handler = Mangum(app, lifespan="off")
