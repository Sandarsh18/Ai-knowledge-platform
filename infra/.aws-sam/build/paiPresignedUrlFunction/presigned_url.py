import json
import os
import uuid
import boto3
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    # Handle CORS preflight request
    if event.get('httpMethod') == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                'Access-Control-Allow-Methods': 'POST,OPTIONS'
            },
            'body': ''
        }
    
    try:
        body = json.loads(event.get('body', '{}'))
        filename = body.get('filename', 'document.pdf')
        content_type = body.get('content_type', 'application/pdf')
        
        # Get user ID from auth context
        user_id = event.get('requestContext', {}).get('authorizer', {}).get('jwt', {}).get('claims', {}).get('sub', 'anonymous')
        
        # Generate unique document ID and S3 key
        doc_id = str(uuid.uuid4())
        s3_key = f"uploads/{user_id}/{doc_id}_{filename}"
        
        # Create S3 client
        s3_client = boto3.client('s3')
        bucket_name = os.environ.get('S3_BUCKET', 'pai-pdf-storage')
        
        # Generate presigned URL for PUT operation (5 minutes expiry)
        presigned_url = s3_client.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': bucket_name,
                'Key': s3_key,
                'ContentType': content_type,
                'Metadata': {
                    'doc_id': doc_id,
                    'user_id': user_id,
                    'filename': filename
                }
            },
            ExpiresIn=300  # 5 minutes
        )
        
        print(f"[PRESIGNED-URL] Generated for doc_id: {doc_id}, key: {s3_key}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'upload_url': presigned_url,
                'doc_id': doc_id,
                's3_key': s3_key,
                'expires_in': 300
            })
        }
        
    except Exception as e:
        import traceback
        print("Presigned URL Exception:", repr(e))
        print(traceback.format_exc())
        
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Failed to generate upload URL',
                'debug_info': str(e)
            })
        }
