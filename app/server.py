import os
import boto3
from fastapi import FastAPI, UploadFile, File, HTTPException
from mangum import Mangum

app = FastAPI(title="FileHost Controller")

s3_client = boto3.client("s3")
BUCKET_NAME: str = os.environ["UPLOAD_BUCKET_NAME"]


@app.get("/health")
def check_health():
    # TODO: implement actual health check endpoint
    return {"status": "healthy"}


@app.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    try:
        contents = await file.read()

        s3_client.put_object(
            Bucket=BUCKET_NAME, Key=f"uploads/{file.filename}", Body=contents
        )
        return {"message": "Success", "filename": file.filename}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"S3 storage error: {str(e)}")


handler = Mangum(app, lifespan="off")
