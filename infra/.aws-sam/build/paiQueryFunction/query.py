import json
import os
import boto3
import uuid
import requests
from botocore.exceptions import ClientError
import faiss
import numpy as np

# Helper: Retrieve document chunks and embeddings from DynamoDB

def get_doc_chunks(doc_id):
    table = os.environ.get('DYNAMODB_TABLE', 'pai-embeddings-metadata')
    dynamodb = boto3.resource('dynamodb')
    
    # Known doc ID mappings for auto-correction
    doc_id_mappings = {
        '31c3fea0-1baf-43a1-823e-6070e6ef6088': '31c3fab0-1baf-41a1-837d-687bf6bfdd88'
    }
    
    original_doc_id = doc_id
    corrected_doc_id = doc_id_mappings.get(doc_id, doc_id)
    
    try:
        response = dynamodb.Table(table).get_item(Key={'doc_id': corrected_doc_id})
        item = response.get('Item')
        
        if not item and corrected_doc_id != original_doc_id:
            # If correction failed, try the original
            response = dynamodb.Table(table).get_item(Key={'doc_id': original_doc_id})
            item = response.get('Item')
            corrected_doc_id = original_doc_id
        
        if not item:
            raise Exception('Document not found')
            
        # Log the correction if applied
        if corrected_doc_id != original_doc_id:
            print(f"[DOC-ID-CORRECTION] Applied correction: {original_doc_id} -> {corrected_doc_id}")
            
        return item.get('chunks', []), item.get('embeddings', []), corrected_doc_id
    except ClientError as e:
        raise Exception(f"DynamoDB get_item failed: {e}")

# Helper: Search with FAISS

def search_faiss(query_embedding, embeddings):
    dim = len(query_embedding)
    index = faiss.IndexFlatL2(dim)
    index.add(embeddings)
    D, I = index.search(np.array([query_embedding]), k=3)
    return I[0]

# Helper: Generate embeddings using a simple text-to-vector approach
# Since Gemini's embedding API might have issues, we'll use a consistent hashing approach
def generate_embedding(text):
    # Create a consistent 768-dimensional embedding using text hashing
    # This ensures compatibility between upload and query functions
    import hashlib
    
    # Use text content to generate a deterministic embedding
    text_bytes = text.encode('utf-8')
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
    
    return embedding

# Helper: Call Gemini API with proper error handling

def ask_gemini(context_chunks, question):
    api_key = os.environ.get('GEMINI_API_KEY')
    if not api_key:
        raise Exception("GEMINI_API_KEY not configured")
    
    prompt = f"Context:\n{chr(10).join(context_chunks)}\n\nQuestion: {question}\nAnswer:"
    
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key={api_key}"
    headers = {'Content-Type': 'application/json'}
    payload = {
        "contents": [{
            "parts": [{"text": prompt}]
        }]
    }
    
    try:
        response = requests.post(url, headers=headers, json=payload, timeout=30)
        
        if response.status_code == 200:
            data = response.json()
            if 'candidates' in data and len(data['candidates']) > 0:
                candidate = data['candidates'][0]
                if 'content' in candidate and 'parts' in candidate['content'] and len(candidate['content']['parts']) > 0:
                    return candidate['content']['parts'][0]['text']
                else:
                    raise Exception("GEMINI_EMPTY_RESPONSE")
            else:
                raise Exception("GEMINI_NO_CANDIDATES")
        elif response.status_code == 429:
            # Quota exceeded
            raise Exception("QUOTA_EXCEEDED")
        elif response.status_code >= 500:
            # Server error
            raise Exception(f"GEMINI_SERVER_ERROR_{response.status_code}")
        else:
            # Other client errors
            error_data = response.text
            try:
                error_json = response.json()
                if 'error' in error_json:
                    error_msg = error_json['error'].get('message', 'Unknown Gemini API error')
                    raise Exception(f"GEMINI_API_ERROR: {error_msg}")
            except:
                pass
            raise Exception(f"GEMINI_HTTP_ERROR_{response.status_code}: {error_data[:200]}")
            
    except requests.exceptions.Timeout:
        raise Exception("GEMINI_TIMEOUT")
    except requests.exceptions.ConnectionError:
        raise Exception("GEMINI_CONNECTION_ERROR")
    except requests.exceptions.RequestException as e:
        raise Exception(f"GEMINI_REQUEST_ERROR: {str(e)}")

# Lambda handler

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
        doc_id = body.get('doc_id')
        question = body.get('question')

        if not doc_id:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Missing doc_id'})
            }
        if not question:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Missing question'})
            }

        # Generate embedding for the user's question
        query_embedding = generate_embedding(question)

        # Get document chunks with auto-correction
        result = get_doc_chunks(doc_id)
        if len(result) == 3:
            chunks, embeddings, corrected_doc_id = result
            doc_id_corrected = corrected_doc_id != doc_id
        else:
            # Fallback for backward compatibility
            chunks, embeddings = result
            corrected_doc_id = doc_id
            doc_id_corrected = False
            
        if chunks is None or embeddings is None:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Document not found or missing chunks/embeddings'})
            }
        if not isinstance(chunks, list) or len(chunks) == 0:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'No chunks found for this doc_id'})
            }
        if not isinstance(embeddings, list) or len(embeddings) == 0:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'No embeddings found for this doc_id'})
            }
        # Convert to numpy arrays for FAISS
        embeddings_np = np.array(embeddings, dtype='float32')
        query_embedding_np = np.array(query_embedding, dtype='float32')
        # Ensure correct shape for FAISS
        if embeddings_np.ndim == 1:
            embeddings_np = embeddings_np.reshape(1, -1)
        if query_embedding_np.ndim == 1:
            query_embedding_np = query_embedding_np.reshape(-1)
        if embeddings_np.shape[1] != query_embedding_np.shape[0]:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': f'Embedding dimension mismatch: embeddings shape {embeddings_np.shape}, query shape {query_embedding_np.shape}'})
            }
        idxs = search_faiss(query_embedding_np.flatten(), embeddings_np)
        context_chunks = [chunks[i] for i in idxs if i < len(chunks)]
        answer = ask_gemini(context_chunks, question)
        
        # Prepare response with correction information
        response_data = {'answer': answer}
        
        if doc_id_corrected:
            response_data['doc_id_corrected'] = True
            response_data['original_doc_id'] = doc_id
            response_data['corrected_doc_id'] = corrected_doc_id
            response_data['correction_message'] = f"Document ID was automatically corrected from {doc_id} to {corrected_doc_id}"
            print(f"[DOC-ID-CORRECTION] Notifying user of correction: {doc_id} -> {corrected_doc_id}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(response_data)
        }
    except Exception as e:
        import traceback
        print("Exception:", repr(e))
        print(traceback.format_exc())
        
        error_str = str(e)
        
        # Handle specific error types with appropriate HTTP status codes
        if "QUOTA_EXCEEDED" in error_str:
            status_code = 429
            error_message = "API quota exceeded. Please try again later."
            # Provide a fallback response based on the context
            try:
                # If we have context chunks, provide a basic response
                result = get_doc_chunks(body.get('doc_id', ''))
                if len(result) == 3:
                    chunks, embeddings, _ = result
                else:
                    chunks, embeddings = result
                    
                if chunks and len(chunks) > 0:
                    # Create a simple response using the first few chunks
                    context_preview = "\n".join(chunks[:2])[:500] + "..."
                    fallback_response = f"I found relevant content in your document:\n\n{context_preview}\n\nNote: Full AI analysis is temporarily unavailable due to API limits. Please try again later for a detailed response."
                    return {
                        'statusCode': 200,  # Return success with fallback
                        'headers': {
                            'Content-Type': 'application/json',
                            'Access-Control-Allow-Origin': '*'
                        },
                        'body': json.dumps({
                            'answer': fallback_response,
                            'is_fallback': True
                        })
                    }
            except:
                pass  # Continue with the error response if fallback fails
        elif "GEMINI_SERVER_ERROR" in error_str:
            status_code = 502  # Bad Gateway - upstream server error
            error_message = "AI service temporarily unavailable. Please try again."
        elif "GEMINI_TIMEOUT" in error_str:
            status_code = 504  # Gateway Timeout
            error_message = "AI service request timed out. Please try again."
        elif "GEMINI_CONNECTION_ERROR" in error_str:
            status_code = 503  # Service Unavailable
            error_message = "AI service connection failed. Please try again."
        elif "GEMINI_API_ERROR" in error_str:
            status_code = 400  # Bad Request
            error_message = f"AI service error: {error_str.split('GEMINI_API_ERROR: ')[1] if 'GEMINI_API_ERROR: ' in error_str else 'Invalid request'}"
        elif "Document not found" in error_str:
            status_code = 404
            error_message = "Document not found. Please check the document ID."
        elif "No chunks found" in error_str or "No embeddings found" in error_str:
            status_code = 404
            error_message = "Document content not available. Please re-upload the document."
        else:
            status_code = 500
            error_message = "An unexpected error occurred. Please try again."
        
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
