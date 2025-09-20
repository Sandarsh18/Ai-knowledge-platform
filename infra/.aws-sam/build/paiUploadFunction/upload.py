import json
import base64
import os
import uuid
import io
import requests
import boto3
import numpy as np
from PyPDF2 import PdfReader
from decimal import Decimal
from botocore.exceptions import ClientError

def upload_pdf_to_s3(file_content, filename, user_id):
    """Upload PDF file to S3 bucket"""
    bucket = os.environ.get('S3_BUCKET', 'pai-pdf-storage')
    s3 = boto3.client('s3')
    key = f"{user_id}/{uuid.uuid4()}_{filename}"
    try:
        s3.put_object(Bucket=bucket, Key=key, Body=file_content, ContentType='application/pdf')
        return key
    except ClientError as e:
        raise Exception(f"S3 upload failed: {e}")

def extract_text_from_pdf(file_content):
    pdf_stream = io.BytesIO(file_content)
    reader = PdfReader(pdf_stream)
    text = "\n".join([page.extract_text() or "" for page in reader.pages])
    return text

def chunk_text(text, chunk_size=500):
    return [text[i:i+chunk_size] for i in range(0, len(text), chunk_size)]

def get_embeddings(chunks):
    # Generate embeddings using a consistent text-to-vector approach
    # This ensures compatibility between upload and query functions
    import hashlib
    
    embeddings = []
    for chunk in chunks:
        # Use text content to generate a deterministic embedding
        text_bytes = chunk.encode('utf-8')
        hash_obj = hashlib.sha256(text_bytes)
        
        # Generate 768 dimensions (common embedding size)
        embedding = []
        seed = hash_obj.hexdigest()
        
        for i in range(768):
            # Use different parts of the hash to generate different values
            char_idx = i % len(seed)
            value = ord(seed[char_idx]) / 255.0  # Normalize to 0-1
            # Add some variation based on position
            value = (value + (i * 0.001)) % 1.0
            embedding.append(value)
        
        embeddings.append(embedding)
    
    return np.array(embeddings, dtype=np.float32)

def lambda_handler(event, context):
    try:
        # Handle CORS preflight requests first (before any other processing)
        http_method = event.get('httpMethod') or event.get('requestContext', {}).get('http', {}).get('method')
        
        if http_method == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Methods': 'POST, OPTIONS',
                    'Access-Control-Allow-Headers': 'Content-Type, Authorization, x-filename',
                    'Content-Type': 'application/json'
                },
                'body': json.dumps({'message': 'CORS preflight success'})
            }

        # Check for Cognito identity
        user_id = event.get('requestContext', {}).get('authorizer', {}).get('jwt', {}).get('claims', {}).get('sub', 'anonymous')
        
        # Get filename and auth from query parameters
        query_params = event.get('queryStringParameters') or {}
        filename = query_params.get('filename', 'upload.pdf')
        auth_token = query_params.get('auth', '')
        
        # Handle request body
        body = event.get('body')
        if not body:
            raise ValueError('No file content provided')
            
        if event.get('isBase64Encoded'):
            file_content = base64.b64decode(body)
        else:
            if isinstance(body, str):
                file_content = body.encode('latin-1')
            else:
                file_content = body
        doc_id = str(uuid.uuid4())
        print(f"[UPLOAD-TRACE] Generated doc_id: {doc_id}")
        print(f"[UPLOAD-TRACE] Request ID: {context.aws_request_id if context else 'N/A'}")
        print(f"[UPLOAD-TRACE] User ID: {user_id}")
        print(f"[UPLOAD-TRACE] Filename: {filename}")
        s3_key = upload_pdf_to_s3(file_content, filename, user_id)
        print(f"S3 upload successful, key: {s3_key}")
        text = extract_text_from_pdf(file_content)
        print(f"Text extraction successful, length: {len(text)}")
        chunks = chunk_text(text)
        embeddings = get_embeddings(chunks)
        # Store all data in DynamoDB in a single operation
        table = os.environ.get('DYNAMODB_TABLE', 'pai-embeddings-metadata')
        dynamodb = boto3.resource('dynamodb')
        # Convert all floats in embeddings to Decimal
        embeddings_decimal = [[Decimal(str(x)) for x in emb] for emb in embeddings.tolist()]
        
        # Store everything in one put_item operation
        print(f"Attempting to store document with doc_id: {doc_id}")
        print(f"Table name: {table}")
        print(f"Number of chunks: {len(chunks)}")
        print(f"Number of embeddings: {len(embeddings_decimal)}")
        
        try:
            response = dynamodb.Table(table).put_item(
                Item={
                    'doc_id': doc_id,
                    'user_id': user_id,
                    'filename': filename,
                    's3_key': s3_key,
                    'chunks': chunks,
                    'embeddings': embeddings_decimal
                }
            )
            print(f"DynamoDB put_item successful: {response}")
            print(f"About to return doc_id: {doc_id}")
        except ClientError as db_error:
            error_code = db_error.response['Error']['Code']
            print(f"DynamoDB ClientError - Code: {error_code}, Message: {str(db_error)}")
            raise Exception(f"Database storage failed: {error_code}")
        except Exception as db_error:
            print(f"DynamoDB error: {str(db_error)}")
            raise Exception(f"Database storage failed: {str(db_error)}")
        
        # Final verification before returning
        response_data = {'doc_id': doc_id, 's3_key': s3_key}
        print(f"[UPLOAD-TRACE] Final response body: {json.dumps(response_data)}")
        print(f"[UPLOAD-TRACE] Doc_id verification - stored: {doc_id}, returning: {response_data['doc_id']}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type, Authorization, x-filename'
            },
            'body': json.dumps(response_data)
        }
    except Exception as e:
        import traceback
        print("Upload Exception:", repr(e))
        print(traceback.format_exc())
        
        error_str = str(e)
        
        # Handle specific error types with appropriate HTTP status codes
        if "S3 upload failed" in error_str:
            status_code = 502  # Bad Gateway - S3 service error
            error_message = "File storage failed. Please try again."
        elif "Database storage failed" in error_str:
            status_code = 503  # Service Unavailable - Database error
            error_message = "Document processing failed. Please try again."
        elif "No file content provided" in error_str:
            status_code = 400  # Bad Request
            error_message = "No file content provided. Please select a PDF file."
        elif "PDF" in error_str or "extract" in error_str.lower():
            status_code = 422  # Unprocessable Entity
            error_message = "Invalid PDF file or unable to extract text. Please check your file."
        else:
            status_code = 500
            error_message = "An unexpected error occurred during upload. Please try again."
        
        return {
            'statusCode': status_code,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': error_message,
                'error_type': error_str.split(':')[0] if ':' in error_str else 'UNKNOWN_ERROR',
                'debug_info': repr(e) if status_code == 500 else None
            })
        }
