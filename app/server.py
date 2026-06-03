import os
import boto3
import ulid
from fastapi import FastAPI, UploadFile, File, HTTPException, Request
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
async def upload_file(request: Request, file: UploadFile = File(...)):
    try:
        contents = await file.read()

        if file.filename is None:
            raise HTTPException(
                    status_code=400,
                    detail="File cannot be empty"
            )

        new_ulid = ulid.new()
        saved_filename = f"{new_ulid}.{file.filename.split('.')[-1]}"

        s3_client.put_object(
            Bucket=BUCKET_NAME,
            Key=f"uploads/{saved_filename}",
            Body=contents
        )

        file_url = f"{str(request.base_url)}files/{saved_filename}"

        return {"message": "Success", "url": file_url}
    except HTTPException as e:
        raise e
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"S3 storage error: {str(e)}")

@app.get("/files/{file_name}/info")
def get_file_information(file_name: str):
    """
    Retrieves metadata for a specific file based on its unique FileId
    """
    try:
        response = table.get_item(Key={"FileName": file_name})
        item = response.get("Item")

        if not item:
            raise HTTPException(
                    status_code=404,
                    detail=f"File with ID '{file_name}' does not exist."
                    )

        return item
    except HTTPException as e:
        raise e
    except Exception as e:
        print(f"Database error while fetching FileId {file_name}: {str(e)}")
        raise HTTPException(
                status_code=500,
                detail="An internal server error occurred while retrieving file information."
                )

handler = Mangum(app, lifespan="off")
