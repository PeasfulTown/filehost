import os
import boto3
from flask import Flask, request, jsonify

app = Flask(__name__)
s3_client = boto3.client('s3')

BUCKET_NAME = os.environ.get("UPLOAD_BUCKET_NAME")

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return jsonify({"error": "No file part"}), 400

    file = request.files['file']
    if file.filename == '':
        return jsonify({"error": "No selected file"}), 400

    try:
        # Stream the file directly to S3
        s3_client.upload_fileobj(file, BUCKET_NAME, file.filename)
        return jsonify({"message": f"Successfully uploaded {file.filename} to S3"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
