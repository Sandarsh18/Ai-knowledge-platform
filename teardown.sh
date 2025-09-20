#!/bin/bash
set -euo pipefail

# Personal AI Knowledge Platform - Teardown Script
# This script removes all AWS resources created by deploy.sh
#
# Usage:
#   ./teardown.sh              # Delete all PAI platform resources
#   AWS_PROFILE=myprofile ./teardown.sh  # Use specific AWS profile
#
# Note: If CloudFormation deletion fails due to Service Control Policy (SCP)
# restrictions, this script will fall back to manual resource deletion.

# Colors for logging
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

print_info()    { echo -e "${BLUE}ℹ $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error()   { echo -e "${RED}❌ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

AWS_REGION="${AWS_REGION:-ap-south-1}"
AWS_PROFILE="${AWS_PROFILE:-default}"

# Resource names must match those in deploy.sh
S3_BUCKET_NAME_PATTERN="pai-pdf-storage-*"
DYNAMO_TABLE="pai-embeddings-metadata"
COGNITO_USER_POOL_NAME="pai-user-pool"
COGNITO_CLIENT_NAME="pai-client"
SECRET_NAME="pai-gemini-api-key"
LAMBDA_LAYER="pai-faiss-layer"
STACK_NAME="pai-stack"
IAM_USER="pai-deployment-user"
IAM_POLICY="pai-deployment-policy"

print_info "Starting teardown in region: $AWS_REGION (profile: $AWS_PROFILE)"

# 1. Delete CloudFormation stack (will remove many resources automatically)
print_info "Deleting CloudFormation stack $STACK_NAME (if exists)..."
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
  print_info "Stack exists, attempting deletion..."
  aws cloudformation delete-stack \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" || {
    print_error "CloudFormation stack deletion failed - likely due to SCP restrictions"
    print_info "Will proceed with manual resource cleanup..."
  }
  
  # Wait for deletion (with timeout)
  print_info "Waiting for stack deletion (max 10 minutes)..."
  timeout 600 aws cloudformation wait stack-delete-complete \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" || {
    print_error "Stack deletion timed out or failed - continuing with manual cleanup"
  }
else
  print_info "CloudFormation stack $STACK_NAME does not exist"
fi

# 2. Delete Lambda functions (manual cleanup in case stack deletion failed)
print_info "Deleting Lambda functions..."
for function_name in pai-upload pai-query pai-presigned-url pai-process-upload; do
  if aws lambda get-function --function-name "$function_name" --region "$AWS_REGION" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
    print_info "Deleting Lambda function: $function_name"
    aws lambda delete-function --function-name "$function_name" --region "$AWS_REGION" --profile "$AWS_PROFILE" || true
  fi
done

# 3. Delete API Gateway (manual cleanup)
print_info "Deleting API Gateway..."
API_ID=$(aws apigatewayv2 get-apis --region "$AWS_REGION" --profile "$AWS_PROFILE" --query 'Items[?Name==`pai-api`].ApiId' --output text 2>/dev/null || true)
if [[ -n "$API_ID" && "$API_ID" != "None" ]]; then
  print_info "Deleting API Gateway: $API_ID"
  aws apigatewayv2 delete-api --api-id "$API_ID" --region "$AWS_REGION" --profile "$AWS_PROFILE" || true
fi

# 4. Empty and delete S3 buckets
print_info "Deleting S3 buckets..."
for bucket in $(aws s3api list-buckets --query "Buckets[].Name" --output text --profile "$AWS_PROFILE" 2>/dev/null || true); do
  if [[ $bucket == pai-pdf-storage* ]]; then
    print_info "Emptying and deleting bucket $bucket"
    aws s3 rm "s3://$bucket" --recursive --profile "$AWS_PROFILE" || true
    aws s3api delete-bucket --bucket "$bucket" --region "$AWS_REGION" --profile "$AWS_PROFILE" || true
    print_success "Deleted S3 bucket: $bucket"
  fi
done

# 5. Delete DynamoDB table
print_info "Deleting DynamoDB table $DYNAMO_TABLE (if exists)..."
if aws dynamodb describe-table --table-name "$DYNAMO_TABLE" --region "$AWS_REGION" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
  aws dynamodb delete-table \
    --table-name "$DYNAMO_TABLE" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" || true
  print_success "Deleted DynamoDB table: $DYNAMO_TABLE"
else
  print_info "DynamoDB table $DYNAMO_TABLE does not exist"
fi

# 6. Delete Cognito resources
print_info "Deleting Cognito user pool and client..."
USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 20 --region "$AWS_REGION" --query "UserPools[?Name=='$COGNITO_USER_POOL_NAME'].Id" --output text --profile "$AWS_PROFILE" 2>/dev/null || true)
if [[ -n "$USER_POOL_ID" && "$USER_POOL_ID" != "None" ]]; then
  print_info "Found user pool: $USER_POOL_ID"
  
  # Delete user pool clients first
  CLIENT_ID=$(aws cognito-idp list-user-pool-clients --user-pool-id "$USER_POOL_ID" --region "$AWS_REGION" --query "UserPoolClients[?ClientName=='$COGNITO_CLIENT_NAME'].ClientId" --output text --profile "$AWS_PROFILE" 2>/dev/null || true)
  if [[ -n "$CLIENT_ID" && "$CLIENT_ID" != "None" ]]; then
    print_info "Deleting user pool client: $CLIENT_ID"
    aws cognito-idp delete-user-pool-client --user-pool-id "$USER_POOL_ID" --client-id "$CLIENT_ID" --region "$AWS_REGION" --profile "$AWS_PROFILE" || true
  fi
  
  # Delete user pool domain if exists
  DOMAIN_PREFIX=$(aws cognito-idp describe-user-pool --user-pool-id "$USER_POOL_ID" --region "$AWS_REGION" --profile "$AWS_PROFILE" --query 'UserPool.Domain' --output text 2>/dev/null || true)
  if [[ -n "$DOMAIN_PREFIX" && "$DOMAIN_PREFIX" != "None" ]]; then
    print_info "Deleting user pool domain: $DOMAIN_PREFIX"
    aws cognito-idp delete-user-pool-domain --domain "$DOMAIN_PREFIX" --region "$AWS_REGION" --profile "$AWS_PROFILE" || true
  fi
  
  # Delete user pool
  print_info "Deleting user pool: $USER_POOL_ID"
  aws cognito-idp delete-user-pool --user-pool-id "$USER_POOL_ID" --region "$AWS_REGION" --profile "$AWS_PROFILE" || true
  print_success "Deleted Cognito user pool: $COGNITO_USER_POOL_NAME"
else
  print_info "Cognito user pool $COGNITO_USER_POOL_NAME does not exist"
fi

# 7. Delete Lambda layer
print_info "Deleting Lambda layer $LAMBDA_LAYER (if exists)..."
if aws lambda get-layer-version --layer-name "$LAMBDA_LAYER" --version-number 1 --region "$AWS_REGION" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
  for version in $(aws lambda list-layer-versions --layer-name "$LAMBDA_LAYER" --region "$AWS_REGION" --query "LayerVersions[].Version" --output text --profile "$AWS_PROFILE" 2>/dev/null || true); do
    if [[ -n "$version" && "$version" != "None" ]]; then
      print_info "Deleting layer version: $version"
      aws lambda delete-layer-version --layer-name "$LAMBDA_LAYER" --version-number "$version" --region "$AWS_REGION" --profile "$AWS_PROFILE" || true
    fi
  done
  print_success "Deleted Lambda layer: $LAMBDA_LAYER"
else
  print_info "Lambda layer $LAMBDA_LAYER does not exist"
fi

# 8. Delete secret
print_info "Deleting Secrets Manager secret $SECRET_NAME (if exists)..."
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
  aws secretsmanager delete-secret \
    --secret-id "$SECRET_NAME" \
    --force-delete-without-recovery \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" || true
  print_success "Deleted secret: $SECRET_NAME"
else
  print_info "Secret $SECRET_NAME does not exist"
fi

# 9. Delete IAM resources (if you want to clean up the deployment user)
print_info "Cleaning up IAM resources..."
if aws iam get-user --user-name "$IAM_USER" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
  print_info "Attempting to clean up IAM user $IAM_USER..."
  
  # Detach policies
  aws iam detach-user-policy --user-name "$IAM_USER" --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess" --profile "$AWS_PROFILE" || true
  
  # Get account ID for custom policy ARN
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile "$AWS_PROFILE" 2>/dev/null || true)
  if [[ -n "$ACCOUNT_ID" ]]; then
    aws iam detach-user-policy --user-name "$IAM_USER" --policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/$IAM_POLICY" --profile "$AWS_PROFILE" || true
    
    # Delete custom policy
    aws iam delete-policy --policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/$IAM_POLICY" --profile "$AWS_PROFILE" || true
  fi
  
  # Delete access keys
  for key in $(aws iam list-access-keys --user-name "$IAM_USER" --query "AccessKeyMetadata[].AccessKeyId" --output text --profile "$AWS_PROFILE" 2>/dev/null || true); do
    if [[ -n "$key" && "$key" != "None" ]]; then
      aws iam delete-access-key --user-name "$IAM_USER" --access-key-id "$key" --profile "$AWS_PROFILE" || true
    fi
  done
  
  # Delete user
  aws iam delete-user --user-name "$IAM_USER" --profile "$AWS_PROFILE" || true
  print_success "Deleted IAM user: $IAM_USER"
else
  print_info "IAM user $IAM_USER does not exist"
fi

echo ""
print_success "🧹 Teardown complete!"
print_info "📋 Summary:"
print_info "  - CloudFormation stack: $STACK_NAME"
print_info "  - Lambda functions: pai-upload, pai-query, pai-presigned-url, pai-process-upload"
print_info "  - API Gateway: pai-api"
print_info "  - S3 buckets: pai-pdf-storage-*"  
print_info "  - DynamoDB table: $DYNAMO_TABLE"
print_info "  - Cognito user pool: $COGNITO_USER_POOL_NAME"
print_info "  - Lambda layer: $LAMBDA_LAYER"
print_info "  - Secret: $SECRET_NAME"
print_info "  - IAM user: $IAM_USER"
echo ""
print_info "⚠️  Note: If CloudFormation deletion failed due to SCP restrictions,"
print_info "   manual resource cleanup was performed instead."
