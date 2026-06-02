import os
import io
import pytest
from fastapi.testclient import TestClient
from moto import mock_aws
import boto3

# Mock out the environment before importing the server.py
# Otherwise server.py will crash immediately looking for UPLOAD_BUCKET_NAME.
os.environ["AWS_ACCESS_KEY_ID"] = "testing"
os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"
os.environ["AWS_SECURITY_TOKEN"] = "testing"
os.environ["AWS_SESSION_TOKEN"] = "testing"
os.environ["AWS_DEFAULT_REGION"] = "us-east-1"
os.environ["UPLOAD_BUCKET_NAME"] = "my-test-bucket"

@pytest.fixture
def client():
    from server import app

    """Provides a fresh FastAPI TestClient for each test."""
    with TestClient(app) as c:
        yield c

@pytest.fixture
def mocked_s3():
    """Fakes the entire S3 service environment locally in-memory."""
    with mock_aws():
        s3 = boto3.client("s3", region_name="us-east-1")
        # Create bucket that the server will push files into
        s3.create_bucket(Bucket="my-test-bucket")
        yield s3

# ============================================================
# TESTS
# ============================================================
def test_health_endpoint(client):
    """Tests that the /health route responds correctly."""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_upload_file_success(client, mocked_s3):
    """Tests a successful multi-part file upload to the S3 bucket."""
    # Create fake file data in memory
    file_name = "sample_document.pdf"
    file_content = b"Fake PDF binary details here."

    # Simulate a multi-part form file upload
    files = {"file": (file_name, io.BytesIO(file_content), "application/pdf")}

    # Execute the client POST request
    response = client.post("/upload", files=files)

    # Assert HTTP response codes and structures match your application rules
    assert response.status_code == 200
    assert response.json() == {"message": "Success", "filename": file_name}

    # VERIFY THE CORE INFRASTRUCTURE: Reach into virtual in-memory S3 bucket
    # to guarantee the file actually landed in the right directory key structure
    s3_objects = mocked_s3.list_objects_v2(Bucket="my-test-bucket")
    assert "Contents" in s3_objects

    s3_object_filename = s3_objects["Contents"][0]["Key"].split('/')[-1]
    assert s3_object_filename == file_name


def test_upload_file_s3_failure(client):
    """Tests how your app handles internal server errors if S3 acts up."""
    # By omitting the 'mocked_s3' fixture setup step here, the 'my-test-bucket'
    # bucket does not exist inside Moto's universe.
    # This forces boto3 to throw a NoSuchBucket exception when called.
    with mock_aws():
        file_name = "broken_upload.txt"
        files = {"file": (file_name, io.BytesIO(b"Hello World"), "text/plain")}

        response = client.post("/upload", files=files)

        # Verify your app catches the exception and returns a structured 500 error
        assert response.status_code == 500
        assert "S3 storage error" in response.json()["detail"]
