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

---

## 🗑️ CLEANUP GUIDE - Delete All Resources

**WARNING: This will permanently delete all your data and resources!**

### Method 1: Delete CloudFormation Stack (Recommended)
```bash
# Delete the main stack (this removes most resources automatically)
aws cloudformation delete-stack --stack-name pai-stack --region ap-south-1

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name pai-stack --region ap-south-1
```

### Method 2: Manual Resource Cleanup (If stack deletion fails)

#### 1. Empty and Delete S3 Bucket:
```bash
# Empty the bucket first
aws s3 rm s3://pai-pdf-storage --recursive

# Delete the bucket
aws s3 rb s3://pai-pdf-storage
```

#### 2. Delete DynamoDB Table:
```bash
aws dynamodb delete-table --table-name pai-embeddings-metadata --region ap-south-1
```

#### 3. Delete Cognito User Pool:
```bash
# Get User Pool ID
aws cognito-idp list-user-pools --max-results 20 --query 'UserPools[?Name==`pai-user-pool`].Id' --output text

# Delete User Pool (replace with actual ID)
aws cognito-idp delete-user-pool --user-pool-id ap-south-1_ig4KDvu8u --region ap-south-1
```

#### 4. Delete Lambda Functions:
```bash
aws lambda delete-function --function-name pai-upload --region ap-south-1
aws lambda delete-function --function-name pai-query --region ap-south-1
aws lambda delete-function --function-name pai-presigned-url --region ap-south-1
aws lambda delete-function --function-name pai-process-upload --region ap-south-1
```

#### 5. Delete API Gateway:
```bash
# List APIs to get the ID
aws apigatewayv2 get-apis --query 'Items[?Name==`pai-api`].ApiId' --output text

# Delete API (replace with actual ID)
aws apigatewayv2 delete-api --api-id <API-ID> --region ap-south-1
```

#### 6. Delete IAM Roles (Created by CloudFormation):
```bash
# List and delete pai-related roles
aws iam list-roles --query 'Roles[?contains(RoleName, `pai`)].RoleName' --output text
# Then delete each role manually or let CloudFormation handle it
```

#### 7. Delete Secrets Manager Secret:
```bash
aws secretsmanager delete-secret --secret-id pai-gemini-api-key --force-delete-without-recovery --region ap-south-1
```

#### 8. Delete SAM Deployment Bucket:
```bash
# Find SAM bucket
aws s3 ls | grep sam-cli-managed

# Empty and delete (replace with actual bucket name)
aws s3 rm s3://aws-sam-cli-managed-default-samclisourcebucket-xxx --recursive
aws s3 rb s3://aws-sam-cli-managed-default-samclisourcebucket-xxx
```

### Verify Cleanup:
```bash
# Check CloudFormation stacks
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE

# Check S3 buckets
aws s3 ls | grep pai

# Check DynamoDB tables
aws dynamodb list-tables --query 'TableNames[?contains(@, `pai`)]'

# Check Lambda functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `pai`)].FunctionName'
```

**Note**: Method 1 (CloudFormation stack deletion) is recommended as it automatically handles dependencies and removes most resources safely.
