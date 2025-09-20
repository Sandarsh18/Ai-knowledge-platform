# Personal AI Knowledge Platform (RAG-based)

This project enables you to upload PDFs and chat with them using Retrieval-Augmented Generation (RAG) powered by OpenAI GPT-4.1. It is built entirely on AWS free tier resources.

## Structure
- `/infra`: AWS SAM templates and infrastructure code
- `/backend`: Lambda functions (Python 3.12)
- `/frontend`: React app

## Features
- User authentication via Cognito
- PDF upload and storage in S3
- Text extraction and embedding storage in DynamoDB
- Vector search with FAISS
- Chat interface powered by GPT-4.1

## Deployment Instructions
1. Install AWS SAM CLI and AWS CLI
2. Configure AWS credentials for region `ap-south-1`
3. Deploy infrastructure:
   ```bash
   cd infra
   sam deploy --guided
   ```
4. Build and deploy backend Lambdas
5. Start frontend React app

See each folder for more details.
