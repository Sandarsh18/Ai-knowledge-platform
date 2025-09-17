<!-- Use this file to provide workspace-specific custom instructions to Copilot. For more details, visit https://code.visualstudio.com/docs/copilot/copilot-customization#_use-a-githubcopilotinstructionsmd-file -->

This project is a Personal AI Knowledge Platform (RAG-based) using AWS SAM, Lambda (Python 3.12), API Gateway HTTP API, Cognito, S3, DynamoDB, and a React frontend. Prefix all resources with 'pai-'.

- Backend: Python 3.12 AWS Lambda
- API: AWS API Gateway HTTP API
- Storage: S3
- Database: DynamoDB
- Auth: Cognito (no client secret)
- AI: OpenAI GPT-4.1 API
- Vector Search: FAISS (Lambda Layer)
- Frontend: React

Follow best practices for AWS free tier usage, CORS, IAM least privilege, and error auto-correction.
