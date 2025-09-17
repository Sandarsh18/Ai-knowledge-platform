# Personal AI Knowledge Platform - Manual Deployment Guide

## Current Status ✅
- Project structure: Complete
- IAM user: Created (`pai-deployment-user`)  
- Gemini API secret: Created in AWS Secrets Manager
- SAM build: Successful
- Code: Updated for Gemini API

## Next Steps (Choose One):

### Option A: AWS Console Deployment (Recommended)
1. Go to AWS Console → CloudFormation → Create Stack
2. Upload template: `infra/.aws-sam/build/template.yaml`
3. Stack name: `pai-stack`
4. Capabilities: Check "I acknowledge IAM resources"
5. Deploy

### Option B: Direct AWS CLI (If console fails)
```bash
aws cloudformation create-stack \
    --stack-name pai-stack \
    --template-body file://infra/.aws-sam/build/template.yaml \
    --capabilities CAPABILITY_IAM \
    --region ap-south-1
```

## After Deployment:

### 1. Get Stack Outputs:
```bash
aws cloudformation describe-stacks \
    --stack-name pai-stack \
    --region ap-south-1 \
    --query 'Stacks[0].Outputs'
```

### 2. Update Frontend Environment:
Copy the outputs to `frontend/.env`:
```
REACT_APP_API_URL=<ApiUrl>
REACT_APP_COGNITO_USER_POOL_ID=<CognitoUserPoolId>  
REACT_APP_COGNITO_USER_POOL_CLIENT_ID=<CognitoUserPoolClientId>
```

### 3. Start Frontend:
```bash
cd frontend
npm install amazon-cognito-identity-js react-router-dom --legacy-peer-deps
npm start
```

## Project Features:
- ✅ User authentication (Cognito)
- ✅ PDF upload to S3  
- ✅ Text extraction and embedding
- ✅ Chat with documents (Gemini AI)
- ✅ Vector search with FAISS
- ✅ React frontend with routing

## Architecture:
- **API**: HTTP API Gateway  
- **Auth**: Cognito User Pool
- **Storage**: S3 + DynamoDB
- **Compute**: Lambda (Python 3.13)
- **AI**: Google Gemini API
- **Frontend**: React with Cognito integration

The platform is fully functional once deployed! 🚀
