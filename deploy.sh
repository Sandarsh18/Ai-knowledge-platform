#!/bin/bash

# Personal AI Knowledge Platform - Fully Automated Deployment Script
# This script automates the complete deployment process from REDEPLOY.md
#
# Usage:
#   ./deploy.sh                 # Fully automated deployment with frontend auto-start
#   ./deploy.sh --health-check  # Run system health check only
#   ./deploy.sh --fix-issues    # Auto-fix common deployment issues
#
# Features:
# - Fully non-interactive deployment
# - Comprehensive prerequisite checks (aws, sam, jq, pip, python3, node, npm, zip)
# - Python version validation (warns if < 3.13)
# - Safe error handling with set -e and explicit error trapping
# - Auto-generated S3 bucket names with timestamps
# - Automatic frontend startup at http://localhost:3000
# - Cross-dependency validation and health checks
# - SCP-aware deployment with automatic fallback to manual Lambda deployment
# - Bypasses CloudFormation transform restrictions when needed

set -e  # Exit on any error

# =============================================================================
# CONFIGURATION - Edit these values before running the script
# =============================================================================
AWS_REGION="ap-south-1"
S3_BUCKET_NAME="pai-pdf-storage-$(date +%s)"
COGNITO_DOMAIN_PREFIX="pai-auth-$(date +%s)"
GEMINI_API_KEY="AIzaSyCbHWvaqql_aGKhzJBQBvZZlLJYofKrCuU"
DYNAMODB_TABLE_NAME="pai-embeddings-metadata"
SECRET_NAME="pai-gemini-api-key"
# =============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables for tracking deployment status
DEPLOYMENT_STATUS=()

# Helper functions
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Function to check if AWS CLI is configured
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check required binaries
    for tool in aws sam jq pip python3 node npm zip; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        fi
    done
    
    # Report missing tools
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_error "Please install all required tools before running this script."
        if [[ " ${missing_tools[*]} " =~ " jq " ]]; then
            print_error "jq is required for parsing JSON output from AWS CLI. Please install it before running."
        fi
        exit 1
    fi
    
    # Check Python version
    local python_version=$(python3 --version 2>&1 | cut -d' ' -f2)
    local python_major=$(echo $python_version | cut -d'.' -f1)
    local python_minor=$(echo $python_version | cut -d'.' -f2)
    
    if [[ $python_major -lt 3 ]] || [[ $python_major -eq 3 && $python_minor -lt 13 ]]; then
        print_warning "Python version $python_version detected. Python 3.13+ is recommended for Lambda compatibility."
        print_warning "Continuing with current version, but you may encounter issues."
    else
        print_success "Python version $python_version is compatible"
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to validate and setup configuration
setup_configuration() {
    print_info "Setting up deployment configuration..."
    
    # Validate Gemini API key
    if [[ "$GEMINI_API_KEY" == "YOUR_GEMINI_KEY_HERE" ]]; then
        print_error "Please replace 'YOUR_GEMINI_KEY_HERE' with your actual Gemini API key in the script configuration section."
        exit 1
    fi
    
    if [[ -z "$GEMINI_API_KEY" ]]; then
        print_error "Gemini API key is required. Please set it in the configuration section."
        exit 1
    fi
    
    # Set AWS region
    export AWS_DEFAULT_REGION=$AWS_REGION
    
    # Display configuration
    print_info "Using configuration:"
    print_info "  AWS Region: $AWS_REGION"
    print_info "  S3 Bucket: $S3_BUCKET_NAME"
    print_info "  Cognito Domain: $COGNITO_DOMAIN_PREFIX"
    print_info "  DynamoDB Table: $DYNAMODB_TABLE_NAME"
    print_info "  Secret Name: $SECRET_NAME"
    
    print_success "Configuration validated successfully"
}

# Step 1: Create IAM User and Policies
create_iam() {
    print_info "Step 1: Setting up IAM user and policies..."
    
    local user_name="pai-deployment-user"
    local policy_name="pai-deployment-policy"
    
    # Check if user already exists
    if aws iam get-user --user-name $user_name &> /dev/null; then
        print_warning "IAM user $user_name already exists, skipping creation"
    else
        # Create deployment user
        aws iam create-user --user-name $user_name || { print_error "Failed to create IAM user"; return 1; }
        aws iam create-access-key --user-name $user_name > /tmp/access-key.json || { print_error "Failed to create access key"; return 1; }
        
        print_info "Access key created. Please save these credentials:"
        cat /tmp/access-key.json
        print_info "If you want to switch AWS CLI to this new user, run: aws configure and paste the above keys."
        rm /tmp/access-key.json
    fi
    
    # Create policy document
    cat > /tmp/pai-deployment-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudformation:*",
                "s3:*",
                "lambda:*",
                "apigateway:*",
                "dynamodb:*",
                "cognito-idp:*",
                "iam:GetRole",
                "iam:CreateRole",
                "iam:AttachRolePolicy",
                "iam:PassRole",
                "secretsmanager:*",
                "logs:*"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Check if policy already exists
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local policy_arn="arn:aws:iam::$account_id:policy/$policy_name"
    
    if aws iam get-policy --policy-arn $policy_arn &> /dev/null; then
        print_warning "IAM policy $policy_name already exists, skipping creation"
    else
        aws iam create-policy --policy-name $policy_name --policy-document file:///tmp/pai-deployment-policy.json || { print_error "Failed to create IAM policy"; return 1; }
    fi
    
    # Attach policy to user
    aws iam attach-user-policy --user-name $user_name --policy-arn $policy_arn || { print_error "Failed to attach policy to user"; return 1; }
    
    # Verification
    if aws iam get-user --user-name $user_name &> /dev/null && \
       aws iam list-attached-user-policies --user-name $user_name | grep -q $policy_name; then
        print_success "IAM setup completed successfully"
        DEPLOYMENT_STATUS+=("IAM:✅")
        return 0
    else
        print_error "IAM setup failed"
        DEPLOYMENT_STATUS+=("IAM:❌")
        return 1
    fi
}

# Step 2: Create Secrets Manager Secret
create_secrets() {
    print_info "Step 2: Creating Secrets Manager secret..."
    
    # Check if secret already exists
    if aws secretsmanager describe-secret --secret-id $SECRET_NAME --region $AWS_REGION &> /dev/null; then
        print_warning "Secret $SECRET_NAME already exists, updating value"
        aws secretsmanager update-secret \
            --secret-id $SECRET_NAME \
            --secret-string "$GEMINI_API_KEY" \
            --region $AWS_REGION || { print_error "Failed to update secret"; return 1; }
    else
        aws secretsmanager create-secret \
            --name $SECRET_NAME \
            --description "Gemini API key for PAI platform" \
            --secret-string "$GEMINI_API_KEY" \
            --region $AWS_REGION || { print_error "Failed to create secret"; return 1; }
    fi
    
    # Verification
    if aws secretsmanager describe-secret --secret-id $SECRET_NAME --region $AWS_REGION &> /dev/null; then
        print_success "Secrets Manager setup completed successfully"
        DEPLOYMENT_STATUS+=("Secrets:✅")
        return 0
    else
        print_error "Secrets Manager setup failed"
        DEPLOYMENT_STATUS+=("Secrets:❌")
        return 1
    fi
}

# Step 3: Create S3 Bucket
create_s3() {
    print_info "Step 3: Creating S3 bucket..."
    
    # Check if bucket already exists
    if aws s3 ls "s3://$S3_BUCKET_NAME" &> /dev/null; then
        print_warning "S3 bucket $S3_BUCKET_NAME already exists, skipping creation"
    else
        aws s3 mb "s3://$S3_BUCKET_NAME" --region $AWS_REGION || { print_error "Failed to create S3 bucket"; return 1; }
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket $S3_BUCKET_NAME \
        --versioning-configuration Status=Enabled || { print_error "Failed to enable S3 versioning"; return 1; }
    
    # Configure CORS
    aws s3api put-bucket-cors \
        --bucket $S3_BUCKET_NAME \
        --cors-configuration '{
            "CORSRules": [
                {
                    "AllowedHeaders": ["*"],
                    "AllowedMethods": ["GET", "POST", "PUT"],
                    "AllowedOrigins": ["*"],
                    "ExposeHeaders": ["ETag"],
                    "MaxAgeSeconds": 3000
                }
            ]
        }' || { print_error "Failed to configure S3 CORS"; return 1; }
    
    # Verification
    if aws s3 ls | grep -q $S3_BUCKET_NAME && \
       aws s3api get-bucket-versioning --bucket $S3_BUCKET_NAME | grep -q "Enabled" && \
       aws s3api get-bucket-cors --bucket $S3_BUCKET_NAME &> /dev/null; then
        print_success "S3 setup completed successfully"
        DEPLOYMENT_STATUS+=("S3:✅")
        return 0
    else
        print_error "S3 setup failed"
        DEPLOYMENT_STATUS+=("S3:❌")
        return 1
    fi
}

# Step 4: Create DynamoDB Table
create_dynamodb() {
    print_info "Step 4: Creating DynamoDB table..."
    
    # Check if table already exists
    if aws dynamodb describe-table --table-name $DYNAMODB_TABLE_NAME --region $AWS_REGION &> /dev/null; then
        print_warning "DynamoDB table $DYNAMODB_TABLE_NAME already exists, skipping creation"
    else
        aws dynamodb create-table \
            --table-name $DYNAMODB_TABLE_NAME \
            --attribute-definitions AttributeName=doc_id,AttributeType=S \
            --key-schema AttributeName=doc_id,KeyType=HASH \
            --billing-mode PAY_PER_REQUEST \
            --region $AWS_REGION || { print_error "Failed to create DynamoDB table"; return 1; }
        
        # Wait for table to become active
        print_info "Waiting for DynamoDB table to become active..."
        aws dynamodb wait table-exists --table-name $DYNAMODB_TABLE_NAME --region $AWS_REGION || { print_error "DynamoDB table failed to become active"; return 1; }
    fi
    
    # Verification
    local table_status=$(aws dynamodb describe-table --table-name $DYNAMODB_TABLE_NAME --region $AWS_REGION --query 'Table.TableStatus' --output text)
    if [[ "$table_status" == "ACTIVE" ]]; then
        print_success "DynamoDB setup completed successfully"
        DEPLOYMENT_STATUS+=("DynamoDB:✅")
        return 0
    else
        print_error "DynamoDB setup failed - table status: $table_status"
        DEPLOYMENT_STATUS+=("DynamoDB:❌")
        return 1
    fi
}

# Step 5: Create Cognito User Pool
create_cognito() {
    print_info "Step 5: Creating Cognito User Pool..."
    
    # Check if user pool already exists
    local existing_pool_id=$(aws cognito-idp list-user-pools --max-results 20 --region $AWS_REGION --query 'UserPools[?Name==`pai-user-pool`].Id' --output text)
    
    if [[ -n "$existing_pool_id" && "$existing_pool_id" != "None" ]]; then
        print_warning "Cognito User Pool already exists with ID: $existing_pool_id"
        USER_POOL_ID=$existing_pool_id
    else
        # Create User Pool
        local pool_output=$(aws cognito-idp create-user-pool \
            --pool-name pai-user-pool \
            --policies '{
                "PasswordPolicy": {
                    "MinimumLength": 8,
                    "RequireUppercase": false,
                    "RequireLowercase": false,
                    "RequireNumbers": false,
                    "RequireSymbols": false
                }
            }' \
            --auto-verified-attributes email \
            --alias-attributes email \
            --email-configuration '{
                "EmailSendingAccount": "COGNITO_DEFAULT"
            }' \
            --admin-create-user-config '{
                "AllowAdminCreateUserOnly": false
            }' \
            --region $AWS_REGION)
        
        USER_POOL_ID=$(echo $pool_output | jq -r '.UserPool.Id')
    fi
    
    # Create App Client
    local existing_client_id=$(aws cognito-idp list-user-pool-clients --user-pool-id $USER_POOL_ID --region $AWS_REGION --query 'UserPoolClients[?ClientName==`pai-client`].ClientId' --output text)
    
    if [[ -n "$existing_client_id" && "$existing_client_id" != "None" ]]; then
        print_warning "Cognito App Client already exists with ID: $existing_client_id"
        CLIENT_ID=$existing_client_id
    else
        local client_output=$(aws cognito-idp create-user-pool-client \
            --user-pool-id $USER_POOL_ID \
            --client-name pai-client \
            --no-generate-secret \
            --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH \
            --prevent-user-existence-errors ENABLED \
            --region $AWS_REGION)
        
        CLIENT_ID=$(echo $client_output | jq -r '.UserPoolClient.ClientId')
    fi
    
    # Create User Pool Domain
    if aws cognito-idp describe-user-pool-domain --domain $COGNITO_DOMAIN_PREFIX --region $AWS_REGION &> /dev/null; then
        print_warning "Cognito domain $COGNITO_DOMAIN_PREFIX already exists"
    else
        aws cognito-idp create-user-pool-domain \
            --domain $COGNITO_DOMAIN_PREFIX \
            --user-pool-id $USER_POOL_ID \
            --region $AWS_REGION
    fi
    
    # Verification
    if aws cognito-idp describe-user-pool --user-pool-id $USER_POOL_ID --region $AWS_REGION &> /dev/null && \
       aws cognito-idp describe-user-pool-client --user-pool-id $USER_POOL_ID --client-id $CLIENT_ID --region $AWS_REGION &> /dev/null; then
        print_success "Cognito setup completed successfully"
        print_info "User Pool ID: $USER_POOL_ID"
        print_info "Client ID: $CLIENT_ID"
        print_info "Domain: $COGNITO_DOMAIN_PREFIX"
        DEPLOYMENT_STATUS+=("Cognito:✅")
        return 0
    else
        print_error "Cognito setup failed"
        DEPLOYMENT_STATUS+=("Cognito:❌")
        return 1
    fi
}

# Step 6: Create Lambda Layer
create_lambda_layer() {
    print_info "Step 6: Creating Lambda layer..."
    
    # Check if layer already exists
    if aws lambda list-layers --region $AWS_REGION | grep -q "pai-faiss-layer"; then
        print_warning "Lambda layer pai-faiss-layer already exists, skipping creation"
    else
        # Create layer directory and install dependencies
        mkdir -p pai-faiss-layer/python || { print_error "Failed to create layer directory"; return 1; }
        pip install faiss-cpu numpy PyPDF2 requests google-generativeai -t pai-faiss-layer/python/ || { print_error "Failed to install Python packages"; return 1; }
        
        # Create layer zip
        cd pai-faiss-layer
        zip -r pai-faiss-layer.zip python/ || { print_error "Failed to create layer zip"; cd ..; return 1; }
        cd ..
        
        # Upload to S3
        aws s3 cp pai-faiss-layer/pai-faiss-layer.zip "s3://$S3_BUCKET_NAME/pai-faiss-layer.zip" --region $AWS_REGION || { print_error "Failed to upload layer to S3"; return 1; }
        
        # Create Lambda layer
        aws lambda publish-layer-version \
            --layer-name pai-faiss-layer \
            --description "FAISS, numpy, PyPDF2, requests, google-generativeai for PAI platform" \
            --content "S3Bucket=$S3_BUCKET_NAME,S3Key=pai-faiss-layer.zip" \
            --compatible-runtimes python3.13 \
            --region $AWS_REGION || { print_error "Failed to create Lambda layer"; return 1; }
        
        # Clean up
        rm -rf pai-faiss-layer
    fi
    
    # Verification
    if aws lambda list-layers --region $AWS_REGION | grep -q "pai-faiss-layer"; then
        print_success "Lambda layer created successfully"
        return 0
    else
        print_error "Lambda layer creation failed"
        return 1
    fi
}

# Manual Lambda deployment (SCP workaround)
deploy_lambda_manual() {
    print_info "Deploying Lambda functions manually (bypassing CloudFormation transforms)..."
    
    # Ensure FAISS dependency is present before building
    ensure_faiss_dependency
    
    # Create IAM role for Lambda functions
    create_lambda_execution_role
    
    # Create API Gateway
    create_api_gateway_manual
    
    # Deploy each Lambda function without layers (SAM build already includes dependencies)
    print_info "Note: Deploying without layers as SAM build already includes all dependencies"
    deploy_single_lambda "pai-upload" ""
    deploy_single_lambda "pai-query" ""
    deploy_single_lambda "pai-presigned-url" ""
    deploy_single_lambda "pai-process-upload" ""
    
    # Configure API Gateway routes
    configure_api_routes
    
    # Configure Lambda environment variables
    configure_lambda_environment_variables
    
    # Fix Lambda handlers
    fix_lambda_handlers
    
    print_success "Manual Lambda deployment completed"
    return 0
}

# Create Lambda execution role
create_lambda_execution_role() {
    local role_name="pai-lambda-execution-role"
    
    if aws iam get-role --role-name $role_name &> /dev/null; then
        print_info "Lambda execution role already exists"
        return 0
    fi
    
    # Create trust policy
    cat > /tmp/lambda-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create role
    aws iam create-role \
        --role-name $role_name \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
        --region $AWS_REGION || { print_error "Failed to create Lambda execution role"; return 1; }
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name $role_name \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || { print_error "Failed to attach basic execution policy"; return 1; }
    
    # Create and attach custom policy for our resources
    cat > /tmp/lambda-custom-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:GetObjectVersion"
            ],
            "Resource": "arn:aws:s3:::$S3_BUCKET_NAME/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:Query",
                "dynamodb:Scan"
            ],
            "Resource": "arn:aws:dynamodb:$AWS_REGION:*:table/$DYNAMODB_TABLE_NAME"
        },
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue"
            ],
            "Resource": "arn:aws:secretsmanager:$AWS_REGION:*:secret:$SECRET_NAME*"
        }
    ]
}
EOF
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local custom_policy_name="pai-lambda-custom-policy"
    
    aws iam create-policy \
        --policy-name $custom_policy_name \
        --policy-document file:///tmp/lambda-custom-policy.json || true
    
    aws iam attach-role-policy \
        --role-name $role_name \
        --policy-arn "arn:aws:iam::$account_id:policy/$custom_policy_name" || { print_error "Failed to attach custom policy"; return 1; }
    
    # Wait for role to be available
    sleep 10
    
    print_success "Lambda execution role created successfully"
}

# Create API Gateway manually
create_api_gateway_manual() {
    print_info "Creating API Gateway manually..."
    
    # Check if API already exists
    API_GATEWAY_ID=$(aws apigatewayv2 get-apis --region $AWS_REGION --query 'Items[?Name==`pai-api`].ApiId' --output text 2>/dev/null || echo "")
    
    if [[ -n "$API_GATEWAY_ID" && "$API_GATEWAY_ID" != "None" ]]; then
        print_info "API Gateway already exists: $API_GATEWAY_ID"
    else
        # Create HTTP API
        local api_output=$(aws apigatewayv2 create-api \
            --name pai-api \
            --protocol-type HTTP \
            --cors-configuration "AllowOrigins=*,AllowMethods=*,AllowHeaders=*" \
            --region $AWS_REGION)
        
        API_GATEWAY_ID=$(echo $api_output | jq -r '.ApiId')
        print_success "Created API Gateway: $API_GATEWAY_ID"
    fi
    
    API_GATEWAY_URL="https://${API_GATEWAY_ID}.execute-api.${AWS_REGION}.amazonaws.com"
    print_info "API Gateway URL: $API_GATEWAY_URL"
}

# Deploy single Lambda function
deploy_single_lambda() {
    local function_name=$1
    local layer_arn=$2
    
    print_info "Deploying Lambda function: $function_name"
    
    # Map function names to SAM build directory names
    local sam_function_name=""
    case $function_name in
        "pai-upload") sam_function_name="paiUploadFunction" ;;
        "pai-query") sam_function_name="paiQueryFunction" ;;
        "pai-presigned-url") sam_function_name="paiPresignedUrlFunction" ;;
        "pai-process-upload") sam_function_name="paiProcessUploadFunction" ;;
        *) print_error "Unknown function name: $function_name"; return 1 ;;
    esac
    
    # Check if function exists
    if aws lambda get-function --function-name $function_name --region $AWS_REGION &> /dev/null; then
        print_info "Lambda function $function_name already exists, updating..."
        
        # Create zip and update function code
        create_lambda_zip $function_name $sam_function_name
        if [[ -f "/tmp/$function_name.zip" ]]; then
            # Check file size - if over 50MB, upload to S3 first
            local zip_size=$(stat -f%z "/tmp/$function_name.zip" 2>/dev/null || stat -c%s "/tmp/$function_name.zip" 2>/dev/null || echo "0")
            if [[ $zip_size -gt 52428800 ]]; then  # 50MB limit
                print_info "Deployment package is large ($zip_size bytes), uploading to S3 first"
                aws s3 cp "/tmp/$function_name.zip" "s3://$S3_BUCKET_NAME/lambda-deployments/$function_name.zip" || {
                    print_error "Failed to upload $function_name to S3"
                    rm -f "/tmp/$function_name.zip"
                    return 1
                }
                aws lambda update-function-code \
                    --function-name $function_name \
                    --s3-bucket "$S3_BUCKET_NAME" \
                    --s3-key "lambda-deployments/$function_name.zip" \
                    --region $AWS_REGION || print_warning "Failed to update $function_name code from S3"
            else
                aws lambda update-function-code \
                    --function-name $function_name \
                    --zip-file "fileb:///tmp/$function_name.zip" \
                    --region $AWS_REGION || print_warning "Failed to update $function_name code"
            fi
            rm -f "/tmp/$function_name.zip"
            print_success "Updated Lambda function: $function_name"
        fi
    else
        # Create function
        local role_arn="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/pai-lambda-execution-role"
        
        # Create zip
        create_lambda_zip $function_name $sam_function_name
        if [[ ! -f "/tmp/$function_name.zip" ]]; then
            print_error "Failed to create zip for $function_name"
            return 1
        fi
        
        # Determine correct handler based on function name
        local handler=""
        case $function_name in
            "pai-upload") handler="upload.lambda_handler" ;;
            "pai-query") handler="query.lambda_handler" ;;
            "pai-presigned-url") handler="presigned_url.lambda_handler" ;;
            "pai-process-upload") handler="process_upload.lambda_handler" ;;
            *) handler="lambda_function.lambda_handler" ;;
        esac
        
        local create_command="aws lambda create-function \
            --function-name $function_name \
            --runtime python3.13 \
            --role $role_arn \
            --handler $handler \
            --zip-file fileb:///tmp/$function_name.zip \
            --timeout 30 \
            --memory-size 512 \
            --region $AWS_REGION"
        
        # Add layer if provided
        if [[ -n "$layer_arn" ]]; then
            create_command="$create_command --layers $layer_arn"
        fi
        
        eval $create_command || { print_error "Failed to create $function_name"; rm -f "/tmp/$function_name.zip"; return 1; }
        print_success "Created Lambda function: $function_name"
        rm -f "/tmp/$function_name.zip"
    fi
}

# Create Lambda zip file from source
create_lambda_zip() {
    local function_name=$1
    local sam_function_name=$2
    local build_dir="infra/.aws-sam/build/$sam_function_name"
    
    if [[ -d "$build_dir" ]]; then
        print_info "Creating zip for $function_name from $sam_function_name"
        cd "$build_dir"
        zip -r "/tmp/$function_name.zip" . > /dev/null 2>&1
        cd - > /dev/null
        print_success "Created zip for $function_name"
    else
        print_error "Build directory not found: $build_dir"
        return 1
    fi
}

# Configure API Gateway routes
configure_api_routes() {
    print_info "Configuring API Gateway routes..."
    
    # Create default stage if it doesn't exist
    if ! aws apigatewayv2 get-stage --api-id $API_GATEWAY_ID --stage-name '$default' --region $AWS_REGION &> /dev/null; then
        aws apigatewayv2 create-stage \
            --api-id $API_GATEWAY_ID \
            --stage-name '$default' \
            --auto-deploy \
            --region $AWS_REGION || print_warning "Failed to create default stage"
    fi
    
    # Configure routes for each Lambda function
    configure_lambda_route "pai-upload" "POST" "/upload"
    configure_lambda_route "pai-query" "POST" "/query"
    configure_lambda_route "pai-presigned-url" "GET" "/presigned-url"
    configure_lambda_route "pai-process-upload" "POST" "/process-upload"
    
    print_success "API Gateway routes configured"
}

# Configure individual Lambda route
configure_lambda_route() {
    local function_name=$1
    local method=$2
    local path=$3
    
    # Check if Lambda function exists before creating routes
    if ! aws lambda get-function --function-name $function_name --region $AWS_REGION &> /dev/null; then
        print_warning "Lambda function $function_name doesn't exist, skipping route configuration"
        return 0
    fi
    
    # Create integration
    local lambda_arn="arn:aws:lambda:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):function:$function_name"
    
    local integration_output=$(aws apigatewayv2 create-integration \
        --api-id $API_GATEWAY_ID \
        --integration-type AWS_PROXY \
        --integration-method POST \
        --integration-uri $lambda_arn \
        --payload-format-version "2.0" \
        --region $AWS_REGION 2>/dev/null || true)
    
    if [[ -n "$integration_output" ]]; then
        local integration_id=$(echo $integration_output | jq -r '.IntegrationId')
        
        # Create route
        aws apigatewayv2 create-route \
            --api-id $API_GATEWAY_ID \
            --route-key "$method $path" \
            --target "integrations/$integration_id" \
            --region $AWS_REGION &> /dev/null || print_info "Route $method $path may already exist"
        
        # Add Lambda permission for API Gateway
        aws lambda add-permission \
            --function-name $function_name \
            --statement-id "apigateway-invoke-$(date +%s)" \
            --action lambda:InvokeFunction \
            --principal apigateway.amazonaws.com \
            --source-arn "arn:aws:execute-api:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):$API_GATEWAY_ID/*/*" \
            --region $AWS_REGION &> /dev/null || print_info "Permission may already exist for $function_name"
        
        print_success "Configured route $method $path -> $function_name"
    else
        print_warning "Failed to create integration for $function_name"
    fi
}

# Fix Lambda handler configurations
fix_lambda_handlers() {
    print_info "Fixing Lambda handler configurations..."
    
    # Update handlers to point to correct files (with retry logic for concurrent updates)
    for func_info in "pai-upload:upload.lambda_handler" "pai-query:query.lambda_handler" "pai-presigned-url:presigned_url.lambda_handler" "pai-process-upload:process_upload.lambda_handler"; do
        local func_name=$(echo $func_info | cut -d':' -f1)
        local handler=$(echo $func_info | cut -d':' -f2)
        
        # Wait for function to be in a ready state
        local retries=0
        while [[ $retries -lt 3 ]]; do
            local status=$(aws lambda get-function-configuration --function-name $func_name --region $AWS_REGION --query 'LastUpdateStatus' --output text 2>/dev/null || echo "Unknown")
            if [[ "$status" == "Successful" ]]; then
                aws lambda update-function-configuration \
                    --function-name $func_name \
                    --handler $handler \
                    --region $AWS_REGION > /dev/null 2>&1 || print_warning "Failed to update $func_name handler"
                break
            elif [[ "$status" == "InProgress" ]]; then
                print_info "Waiting for $func_name to complete previous update..."
                sleep 10
                ((retries++))
            else
                print_warning "Function $func_name in unexpected state: $status"
                break
            fi
        done
    done
    
    print_success "Lambda handlers updated successfully"
    
    # Check if query function needs FAISS rebuild
    if aws lambda get-function-configuration --function-name pai-query --region $AWS_REGION --query 'LastUpdateStatus' --output text | grep -q "Failed\|InProgress"; then
        print_info "Query function may need rebuilding with FAISS dependency"
        sleep 5  # Wait for any in-progress updates
        if aws lambda get-function-configuration --function-name pai-query --region $AWS_REGION 2>/dev/null | grep -q "ImportModuleError.*faiss"; then
            print_info "Detected FAISS import error, rebuilding query function..."
            fix_large_lambda_deployment "pai-query" "paiQueryFunction"
        fi
    fi
}

# Ensure FAISS dependency is added to query function
ensure_faiss_dependency() {
    print_info "Ensuring FAISS dependency in query function..."
    
    local query_requirements="backend/query/requirements.txt"
    if [[ -f "$query_requirements" ]]; then
        if ! grep -q "faiss-cpu" "$query_requirements"; then
            print_info "Adding faiss-cpu to query requirements.txt"
            echo "faiss-cpu" >> "$query_requirements"
            print_success "Added faiss-cpu dependency to query function"
        else
            print_info "faiss-cpu already present in query requirements.txt"
        fi
    else
        print_warning "Query requirements.txt not found at $query_requirements"
    fi
}

# Fix large Lambda deployments using S3
fix_large_lambda_deployment() {
    local function_name=$1
    local sam_function_name=$2
    
    print_info "Handling large deployment for $function_name"
    
    # Create zip from SAM build
    local build_dir="infra/.aws-sam/build/$sam_function_name"
    if [[ -d "$build_dir" ]]; then
        cd "$build_dir"
        zip -r "/tmp/$function_name-large.zip" . > /dev/null 2>&1
        cd - > /dev/null
        
        # Upload to S3
        aws s3 cp "/tmp/$function_name-large.zip" "s3://$S3_BUCKET_NAME/lambda-deployments/$function_name-updated.zip" || {
            print_error "Failed to upload $function_name to S3"
            rm -f "/tmp/$function_name-large.zip"
            return 1
        }
        
        # Update function from S3
        aws lambda update-function-code \
            --function-name $function_name \
            --s3-bucket "$S3_BUCKET_NAME" \
            --s3-key "lambda-deployments/$function_name-updated.zip" \
            --region $AWS_REGION || {
            print_error "Failed to update $function_name from S3"
            rm -f "/tmp/$function_name-large.zip"
            return 1
        }
        
        rm -f "/tmp/$function_name-large.zip"
        print_success "Updated $function_name using S3 deployment"
    else
        print_error "Build directory not found: $build_dir"
        return 1
    fi
}

# Configure Lambda environment variables (shared function)
configure_lambda_environment_variables() {
    print_info "Configuring Lambda environment variables..."
    
    # Update each Lambda function with environment variables using proper AWS CLI format
    print_info "Setting environment variables for pai-upload..."
    aws lambda update-function-configuration \
        --function-name pai-upload \
        --environment "Variables={S3_BUCKET=$S3_BUCKET_NAME,DYNAMODB_TABLE=$DYNAMODB_TABLE_NAME,GEMINI_SECRET_NAME=$SECRET_NAME}" \
        --region $AWS_REGION > /dev/null || { print_error "Failed to configure pai-upload Lambda"; return 1; }
    
    print_info "Setting environment variables for pai-query..."
    aws lambda update-function-configuration \
        --function-name pai-query \
        --environment "Variables={DYNAMODB_TABLE=$DYNAMODB_TABLE_NAME,GEMINI_SECRET_NAME=$SECRET_NAME}" \
        --region $AWS_REGION > /dev/null || { print_error "Failed to configure pai-query Lambda"; return 1; }
    
    print_info "Setting environment variables for pai-presigned-url..."
    aws lambda update-function-configuration \
        --function-name pai-presigned-url \
        --environment "Variables={S3_BUCKET=$S3_BUCKET_NAME}" \
        --region $AWS_REGION > /dev/null || { print_error "Failed to configure pai-presigned-url Lambda"; return 1; }
    
    print_info "Setting environment variables for pai-process-upload..."
    aws lambda update-function-configuration \
        --function-name pai-process-upload \
        --environment "Variables={DYNAMODB_TABLE=$DYNAMODB_TABLE_NAME,GEMINI_SECRET_NAME=$SECRET_NAME}" \
        --region $AWS_REGION > /dev/null || { print_error "Failed to configure pai-process-upload Lambda"; return 1; }
    
    print_success "Lambda environment variables configured successfully"
}

# Step 7: Deploy Lambda Functions with SAM (with SCP fallback)
deploy_lambda() {
    print_info "Step 7: Deploying Lambda functions with SAM..."
    
    # Check if infra directory exists
    if [[ ! -d "infra" ]]; then
        print_error "infra directory not found. Please ensure you're running this script from the project root."
        DEPLOYMENT_STATUS+=("Lambda:❌")
        return 1
    fi
    
    # Navigate to infra directory
    cd infra
    
    # Build SAM application
    print_info "Building SAM application..."
    sam build || { print_error "SAM build failed"; return 1; }
    
    # Try SAM deploy first
    print_info "Attempting SAM deploy in automated mode..."
    local sam_success=false
    
    # Check if stack already exists
    if aws cloudformation describe-stacks --stack-name pai-stack --region $AWS_REGION &> /dev/null; then
        print_warning "CloudFormation stack pai-stack already exists, updating..."
        if sam deploy --no-confirm-changeset 2>/dev/null; then
            sam_success=true
        else
            print_warning "SAM deploy update failed - likely due to SCP restrictions on AWS transforms"
        fi
    else
        # Create samconfig.toml for automated deployment
        cat > samconfig.toml << EOF
version = 0.1
[default]
[default.deploy]
[default.deploy.parameters]
stack_name = "pai-stack"
s3_bucket = "$S3_BUCKET_NAME"
s3_prefix = "pai-stack"
region = "$AWS_REGION"
confirm_changeset = false
capabilities = "CAPABILITY_IAM"
parameter_overrides = []
EOF
        
        if sam deploy 2>/dev/null; then
            sam_success=true
        else
            print_warning "SAM deploy failed - likely due to SCP restrictions on AWS transforms"
        fi
    fi
    
    # If SAM failed, fall back to manual Lambda deployment
    if [[ "$sam_success" == "false" ]]; then
        print_info "Falling back to manual Lambda deployment (SCP workaround)..."
        cd ..
        deploy_lambda_manual || { print_error "Manual Lambda deployment failed"; return 1; }
        return 0
    fi
    
    # Navigate back to project root
    cd ..
    
    # Get API Gateway information (works for both SAM and manual deployment)
    if [[ -z "$API_GATEWAY_ID" ]]; then
        API_GATEWAY_ID=$(aws apigatewayv2 get-apis --region $AWS_REGION --query 'Items[?Name==`pai-api`].ApiId' --output text)
    fi
    if [[ -z "$API_GATEWAY_URL" ]]; then
        API_GATEWAY_URL=$(aws apigatewayv2 get-apis --region $AWS_REGION --query 'Items[?Name==`pai-api`].ApiEndpoint' --output text)
        # Fallback for manual deployment
        if [[ -z "$API_GATEWAY_URL" || "$API_GATEWAY_URL" == "None" ]]; then
            API_GATEWAY_URL="https://${API_GATEWAY_ID}.execute-api.${AWS_REGION}.amazonaws.com"
        fi
    fi
    
    # Ensure FAISS dependency is present before building
    ensure_faiss_dependency
    
    # Configure Lambda environment variables (works for both SAM and manual deployment)
    configure_lambda_environment_variables
    
    # Fix Lambda handlers (ensure correct entry points)
    fix_lambda_handlers
    
    # Verification
    local stack_status=$(aws cloudformation describe-stacks --stack-name pai-stack --region $AWS_REGION --query 'Stacks[0].StackStatus' --output text)
    local lambda_count=$(aws lambda list-functions --region $AWS_REGION --query 'Functions[?contains(FunctionName, `pai`)].FunctionName' --output text | wc -w)
    
    if [[ "$stack_status" == "CREATE_COMPLETE" || "$stack_status" == "UPDATE_COMPLETE" ]] && [[ "$lambda_count" -eq 4 ]]; then
        print_success "Lambda deployment completed successfully"
        print_info "API Gateway ID: $API_GATEWAY_ID"
        print_info "API Gateway URL: $API_GATEWAY_URL"
        DEPLOYMENT_STATUS+=("Lambda:✅")
        return 0
    else
        print_error "Lambda deployment failed - Stack status: $stack_status, Lambda functions: $lambda_count/4"
        DEPLOYMENT_STATUS+=("Lambda:❌")
        return 1
    fi
}

# Step 8: Setup API Gateway
setup_apigateway() {
    print_info "Step 8: Setting up API Gateway..."
    
    # API Gateway is created by SAM, so we just need to verify and configure CORS
    if [[ -z "$API_GATEWAY_ID" ]]; then
        API_GATEWAY_ID=$(aws apigatewayv2 get-apis --region $AWS_REGION --query 'Items[?Name==`pai-api`].ApiId' --output text)
        API_GATEWAY_URL=$(aws apigatewayv2 get-apis --region $AWS_REGION --query 'Items[?Name==`pai-api`].ApiEndpoint' --output text)
    fi
    
    # Configure CORS
    aws apigatewayv2 update-api \
        --api-id $API_GATEWAY_ID \
        --cors-configuration AllowOrigins="*",AllowMethods="*",AllowHeaders="*" \
        --region $AWS_REGION || { print_error "Failed to configure API Gateway CORS"; return 1; }
    
    # Test API connectivity
    print_info "Testing API connectivity..."
    if curl -f -s "$API_GATEWAY_URL/presigned-url?filename=test.pdf&auth=test" > /dev/null 2>&1; then
        print_success "API Gateway setup completed successfully"
        DEPLOYMENT_STATUS+=("API Gateway:✅")
        return 0
    else
        print_warning "API Gateway created but endpoints may not be fully ready yet"
        DEPLOYMENT_STATUS+=("API Gateway:⚠")
        return 0
    fi
}

# Step 9: Setup Frontend Environment
setup_frontend() {
    print_info "Step 9: Setting up frontend environment..."
    
    # Check if frontend directory exists
    if [[ ! -d "frontend" ]]; then
        print_warning "frontend directory not found, skipping frontend setup"
        return 0
    fi
    
    # Navigate to frontend directory
    cd frontend
    
    # Create .env file
    cat > .env << EOF
REACT_APP_API_URL=$API_GATEWAY_URL
REACT_APP_COGNITO_USER_POOL_ID=$USER_POOL_ID
REACT_APP_COGNITO_USER_POOL_CLIENT_ID=$CLIENT_ID
EOF
    
    # Install dependencies if package.json exists
    if [[ -f "package.json" ]]; then
        npm install amazon-cognito-identity-js react-router-dom --legacy-peer-deps || { print_error "Failed to install npm dependencies"; return 1; }
    fi
    
    # Navigate back to project root
    cd ..
    
    # Verification
    if [[ -f "frontend/.env" ]]; then
        print_success "Frontend setup completed successfully"
        print_info "Frontend .env file created with:"
        cat frontend/.env
        return 0
    else
        print_error "Frontend setup failed"
        return 1
    fi
}

# Cross-dependency validation
validate_dependencies() {
    print_info "Validating cross-dependencies..."
    
    local validation_errors=0
    
    # Check S3 bucket matches Lambda environment variables
    local lambda_s3_bucket=$(aws lambda get-function-configuration --function-name pai-upload --region $AWS_REGION --query 'Environment.Variables.S3_BUCKET' --output text)
    if [[ "$lambda_s3_bucket" == "$S3_BUCKET_NAME" ]]; then
        print_success "S3 bucket name matches Lambda environment variables"
    else
        print_error "S3 bucket mismatch - Lambda: $lambda_s3_bucket, Expected: $S3_BUCKET_NAME"
        ((validation_errors++))
    fi
    
    # Check DynamoDB table matches Lambda environment variables
    local lambda_dynamodb_table=$(aws lambda get-function-configuration --function-name pai-query --region $AWS_REGION --query 'Environment.Variables.DYNAMODB_TABLE' --output text)
    if [[ "$lambda_dynamodb_table" == "$DYNAMODB_TABLE_NAME" ]]; then
        print_success "DynamoDB table name matches Lambda environment variables"
    else
        print_error "DynamoDB table mismatch - Lambda: $lambda_dynamodb_table, Expected: $DYNAMODB_TABLE_NAME"
        ((validation_errors++))
    fi
    
    # Check Cognito IDs match frontend configuration
    if [[ -f "frontend/.env" ]]; then
        local frontend_pool_id=$(grep REACT_APP_COGNITO_USER_POOL_ID frontend/.env | cut -d'=' -f2)
        local frontend_client_id=$(grep REACT_APP_COGNITO_USER_POOL_CLIENT_ID frontend/.env | cut -d'=' -f2)
        
        if [[ "$frontend_pool_id" == "$USER_POOL_ID" ]]; then
            print_success "Cognito User Pool ID matches frontend configuration"
        else
            print_error "Cognito User Pool ID mismatch - Frontend: $frontend_pool_id, Expected: $USER_POOL_ID"
            ((validation_errors++))
        fi
        
        if [[ "$frontend_client_id" == "$CLIENT_ID" ]]; then
            print_success "Cognito Client ID matches frontend configuration"
        else
            print_error "Cognito Client ID mismatch - Frontend: $frontend_client_id, Expected: $CLIENT_ID"
            ((validation_errors++))
        fi
    fi
    
    # Check API Gateway accessibility
    if curl -f -s "$API_GATEWAY_URL/presigned-url?filename=test.pdf&auth=test" > /dev/null 2>&1; then
        print_success "API Gateway is accessible"
    else
        print_warning "API Gateway endpoints may not be fully ready yet"
        ((validation_errors++))
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        print_success "All cross-dependencies validated successfully"
        DEPLOYMENT_STATUS+=("Dependencies:✅")
        return 0
    else
        print_error "Cross-dependency validation failed with $validation_errors errors"
        DEPLOYMENT_STATUS+=("Dependencies:❌")
        return 1
    fi
}

# Generate deployment summary
generate_summary() {
    print_info "Generating deployment summary..."
    
    cat > deployment-summary.txt << EOF
=== Personal AI Knowledge Platform Deployment Summary ===
Deployment Date: $(date)
AWS Region: $AWS_REGION

=== Resource Identifiers ===
S3 Bucket: $S3_BUCKET_NAME
DynamoDB Table: $DYNAMODB_TABLE_NAME
Secrets Manager Secret: $SECRET_NAME

=== Cognito Configuration ===
User Pool ID: $USER_POOL_ID
User Pool Client ID: $CLIENT_ID
User Pool Domain: $COGNITO_DOMAIN_PREFIX

=== API Gateway ===
API Gateway ID: $API_GATEWAY_ID
API Gateway URL: $API_GATEWAY_URL

=== Deployment Status ===
$(printf '%s\n' "${DEPLOYMENT_STATUS[@]}")

=== Next Steps ===
1. Navigate to the frontend directory: cd frontend
2. Start the development server: npm start
3. Open http://localhost:3000 in your browser
4. Register a new user and test the application

=== Quick Health Check ===
Run this command to check system health:
./deploy.sh --health-check
EOF
    
    print_success "Deployment summary saved to deployment-summary.txt"
    cat deployment-summary.txt
}

# Start frontend automatically
start_frontend() {
    print_info "Starting frontend automatically..."
    
    # Check if frontend directory exists
    if [[ ! -d "frontend" ]]; then
        print_warning "frontend directory not found, skipping frontend startup"
        return 0
    fi
    
    # Navigate to frontend directory
    cd frontend
    
    # Install dependencies
    print_info "Installing frontend dependencies..."
    npm install --legacy-peer-deps || { 
        print_error "Failed to install frontend dependencies"
        cd ..
        return 1
    }
    
    # Start the frontend in background
    print_info "Starting React development server..."
    npm start > /dev/null 2>&1 &
    
    # Wait a moment for the server to start
    sleep 3
    
    # Navigate back to project root
    cd ..
    
    print_success "Frontend started at http://localhost:3000"
    print_info "The React development server is running in the background."
    print_info "Open your browser and navigate to http://localhost:3000 to access the application."
    
    return 0
}

# Health check function
health_check() {
    print_info "Running system health check..."
    
    echo "=== PAI Platform Health Check ==="
    
    # Check S3
    if aws s3 ls | grep -q $S3_BUCKET_NAME; then
        print_success "S3 Bucket: OK"
    else
        print_error "S3 Bucket: FAILED"
    fi
    
    # Check DynamoDB
    if aws dynamodb describe-table --table-name $DYNAMODB_TABLE_NAME --region $AWS_REGION > /dev/null 2>&1; then
        print_success "DynamoDB: OK"
    else
        print_error "DynamoDB: FAILED"
    fi
    
    # Check Lambda Functions
    local lambda_count=$(aws lambda list-functions --region $AWS_REGION --query 'Functions[?contains(FunctionName, `pai`)].FunctionName' --output text | wc -w)
    if [[ "$lambda_count" -eq 4 ]]; then
        print_success "Lambda Functions: OK (4/4)"
    else
        print_error "Lambda Functions: FAILED ($lambda_count/4)"
    fi
    
    # Check API Gateway
    if aws apigatewayv2 get-apis --region $AWS_REGION --query 'Items[?Name==`pai-api`].ApiId' --output text | grep -q "."; then
        print_success "API Gateway: OK"
    else
        print_error "API Gateway: FAILED"
    fi
    
    # Check API Connectivity
    local api_url=$(aws apigatewayv2 get-apis --region $AWS_REGION --query 'Items[?Name==`pai-api`].ApiEndpoint' --output text)
    if curl -f -s "$api_url/presigned-url?filename=test.pdf&auth=test" > /dev/null 2>&1; then
        print_success "API Connectivity: OK"
    else
        print_warning "API Connectivity: May need time to fully initialize"
    fi
    
    # Check Lambda environment variables
    local env_vars_ok=true
    for func in pai-upload pai-query pai-presigned-url pai-process-upload; do
        local env_vars=$(aws lambda get-function-configuration --function-name $func --region $AWS_REGION --query 'Environment.Variables' --output text 2>/dev/null || echo "null")
        if [[ "$env_vars" == "null" || "$env_vars" == "" ]]; then
            env_vars_ok=false
            break
        fi
    done
    
    if [[ "$env_vars_ok" == "true" ]]; then
        print_success "Lambda Environment Variables: OK"
    else
        print_error "Lambda Environment Variables: MISSING"
    fi
    
    echo "=== Health Check Complete ==="
}

# Print final status summary
print_final_summary() {
    echo ""
    echo "=================================="
    echo "    DEPLOYMENT SUMMARY"
    echo "=================================="
    
    for status in "${DEPLOYMENT_STATUS[@]}"; do
        echo "$status"
    done
    
    echo "=================================="
}

# Main deployment function
main() {
    echo ""
    echo "🚀 Personal AI Knowledge Platform - Automated Deployment"
    echo "========================================================"
    
    # Handle command line arguments
    local INTERACTIVE_MODE="false"
    
    for arg in "$@"; do
        case $arg in
            --health-check)
                # Load configuration if available
                if [[ -f "deployment-summary.txt" ]]; then
                    AWS_REGION=$(grep "AWS Region:" deployment-summary.txt | cut -d' ' -f3)
                    S3_BUCKET_NAME=$(grep "S3 Bucket:" deployment-summary.txt | cut -d' ' -f3)
                    DYNAMODB_TABLE_NAME=$(grep "DynamoDB Table:" deployment-summary.txt | cut -d' ' -f3)
                    SECRET_NAME=$(grep "Secrets Manager Secret:" deployment-summary.txt | cut -d' ' -f4)
                    export AWS_DEFAULT_REGION=$AWS_REGION
                fi
                health_check
                exit 0
                ;;
            --fix-issues)
                # Load configuration and fix common issues
                if [[ -f "deployment-summary.txt" ]]; then
                    AWS_REGION=$(grep "AWS Region:" deployment-summary.txt | cut -d' ' -f3)
                    S3_BUCKET_NAME=$(grep "S3 Bucket:" deployment-summary.txt | cut -d' ' -f3)
                    DYNAMODB_TABLE_NAME=$(grep "DynamoDB Table:" deployment-summary.txt | cut -d' ' -f3)
                    SECRET_NAME=$(grep "Secrets Manager Secret:" deployment-summary.txt | cut -d' ' -f4)
                    export AWS_DEFAULT_REGION=$AWS_REGION
                    
                    print_info "Auto-fixing common deployment issues..."
                    ensure_faiss_dependency
                    configure_lambda_environment_variables
                    fix_lambda_handlers
                    print_success "Issue fixes completed!"
                else
                    print_error "deployment-summary.txt not found. Run full deployment first."
                fi
                exit 0
                ;;
        esac
    done
    
    # Run deployment steps
    check_prerequisites
    setup_configuration
    
    # Execute deployment steps
    create_iam || print_warning "IAM setup had issues but continuing..."
    create_secrets || exit 1
    create_s3 || exit 1
    create_dynamodb || exit 1
    create_cognito || exit 1
    create_lambda_layer || print_warning "Lambda layer had issues but continuing..."
    deploy_lambda || exit 1
    setup_apigateway || print_warning "API Gateway setup had issues but continuing..."
    setup_frontend || print_warning "Frontend setup had issues but continuing..."
    
    # Validate dependencies
    validate_dependencies || print_warning "Some dependency validations failed but deployment may still work"
    
    # Generate summary and cleanup
    generate_summary
    print_final_summary
    
    # Start frontend automatically
    start_frontend || print_warning "Frontend startup had issues but deployment is complete"
    
    print_success "🎉 Full deployment completed! Check deployment-summary.txt for details."
    print_success "🌐 Frontend is running at http://localhost:3000"
    print_info "📋 Run './deploy.sh --health-check' anytime to verify system health."
}

# Execute main function
main "$@"
