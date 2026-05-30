import pytest
from io import BytesIO
from server import app

@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_upload_no_file(client):
    """Test that submitting an empty request returns a 400 error."""
    response = client.post('/upload')
    assert response.status_code == 400
    assert b"No file part" in response.data

def test_upload_success(client, mocker):
    """Test a successful file upload by mocking the external AWS S3 call."""
    # Mock boto3's upload_fileobj so it doesn't actually connect to AWS during our test
    mock_upload = mocker.patch('boto3.client')
    
    data = {
        'file': (BytesIO(b"dummy file content"), 'test_document.txt')
    }
    
    response = client.post('/upload', data=data, content_type='multipart/form-data')
    assert response.status_code == 200
    assert b"Successfully uploaded test_document.txt" in response.data
