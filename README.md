# Introduction

A high-performance, serverless file hosting platform. This project leverages
FastAPI, AWS Lambda, Amazon S3, DynamoDB, and AWS CloudFront to provide
lightning-fast, globally cached file delivery alongside a secure metadata
tracking API.

# Getting Started

Prerequisites:

- Python 3.11+
- Terraform
- AWS CLI configured (permissions for terraform)

1. Clone the repository and go into terraform directory:

```bash
git clone git@github.com:PeasfulTown/fileshare
cd fileshare/terraform
```

2. Use terraform to provision:

```bash
terraform apply
```

Review the plan and type `yes` to start provisioning.

3. Test endpoint:

```bash
curl -X POST "https://$(terraform output -raw cloudfront_url)/upload" \
    -F "file=@/path/to/file/testfile.txt"
```

# System Architecture

Cloudfront acts as the primary reverse proxy, evaluating the path structure to
efficiently split traffic:

- `POST /upload` -> API Gateway -> FastAPI Lambda (writes to S3 & hands back
  CDN URLs)
- `GET /files/{filename}/info` -> API Gateway -> FastAPI Lambda (fetches
  DynamoDB record)
- `GET /files/{filename}` -> S3 Bucket (direct edge delivery via CloudFront OAC)

# API Reference

1. Upload a file

- Method: `POST`
- Path: `/upload`
- Payload: `multipart/form-data` with a key named `file`

Response (`200 OK`):

```json
{
    "message": "Success",
    "url": "https://123abc.cloudfront.net/files/filename.png"
}
```

2. View/Download file

- Method: `GET`
- Path: `/files/{filename}`
- Behavior: Streams the raw asset directly from the nearest CloudFront edge
  location with browser viewport support enabled.

3. Get file metadata

- Method: `GET`
- Path: `/files/{filename}/info`

Response (`200 OK`):

```json
    "FileName": "filename.png",
    "UploadedOn": "2026-06-11T18:47:37.000Z",
    "FileSizeInBytes": 20,
    "ContentType": "image/png"
```

