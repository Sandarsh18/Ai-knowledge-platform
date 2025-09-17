import boto3
import uuid
import os
from botocore.exceptions import ClientError
from decimal import Decimal  # <-- Add this import

def upload_pdf_to_s3(file_content, filename, user_id):
    bucket = os.environ.get('S3_BUCKET', 'pai-pdf-storage')
    s3 = boto3.client('s3')
    key = f"{user_id}/{uuid.uuid4()}_{filename}"
    try:
        s3.put_object(Bucket=bucket, Key=key, Body=file_content, ContentType='application/pdf')
        return key
    except ClientError as e:
        raise Exception(f"S3 upload failed: {e}")

def store_metadata(doc_id, user_id, filename, s3_key):
    table = os.environ.get('DYNAMODB_TABLE', 'pai-embeddings-metadata')
    dynamodb = boto3.resource('dynamodb')
    item = {
        'doc_id': doc_id,
        'user_id': user_id,
        'filename': filename,
        's3_key': s3_key
    }
    # If you ever add float fields, convert them to Decimal here
    for k, v in item.items():
        if isinstance(v, float):
            item[k] = Decimal(str(v))
    try:
        dynamodb.Table(table).put_item(Item=item)
    except ClientError as e:
        raise Exception(f"DynamoDB put_item failed: {e}")
