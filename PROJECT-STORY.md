# Personal AI Knowledge Platform - Full Project Story & Guide

## 1. Project Idea
This project is a Personal AI Knowledge Platform. The goal is to let anyone upload PDF documents and then "chat" with them using AI. For example, you could upload a textbook and ask questions about it, and the AI would answer using the content of your PDF.

## 2. How We Started
We wanted to use only free or very low-cost cloud resources, so we chose AWS (Amazon Web Services) and built everything using their free tier. We also wanted the project to be easy to use, secure, and scalable.

## 3. Main Technologies Used
- **AWS Lambda**: Runs our backend code (Python)
- **API Gateway**: Lets the frontend talk to the backend
- **S3**: Stores uploaded PDFs
- **DynamoDB**: Stores metadata and AI embeddings
- **Cognito**: Handles user login and registration
- **Google Gemini API**: Provides the AI answers
- **FAISS**: Finds the most relevant chunks of text
- **React**: The web frontend

## 4. Project Structure & Why Each File Exists
- `/infra/`: Contains infrastructure code (SAM template)
- `/backend/`: Contains Lambda functions
  - `/upload/`: Handles PDF upload and text extraction
  - `/query/`: Handles chat queries
  - `/common/storage.py`: Helper for S3 and DynamoDB
- `/frontend/`: React app for users
- `.github/copilot-instructions.md`: Custom instructions for Copilot
- `DEPLOYMENT-GUIDE.md`: Step-by-step deployment instructions
- `setup-iam.sh`, `create-deployment-user.sh`: Scripts to set up AWS permissions
- `iam-roles.yaml`: Defines IAM roles and policies

## 5. How We Created Each Part
### Infrastructure
We started with AWS SAM (Serverless Application Model) to define all resources in one file. This makes it easy to deploy everything at once. We used YAML because it's readable and supported by AWS.

### Backend
We wrote Python Lambda functions for upload and query. The upload function:
- Accepts a PDF
- Extracts text
- Splits text into chunks
- Gets AI embeddings for each chunk
- Stores everything in DynamoDB

The query function:
- Accepts a question
- Finds the most relevant chunks using FAISS
- Sends those chunks and the question to Gemini AI
- Returns the answer

### Frontend
We built a React app with:
- Login/Register (using Cognito)
- File upload UI
- Chat interface

### IAM & Security
We created a dedicated IAM user for deployment, with only the permissions needed. We used scripts to automate this and avoid using the root account.

## 6. Commands We Used & Why
- `aws configure`: Set up AWS CLI credentials
- `sam build`: Build the SAM project
- `sam deploy`: Deploy the project to AWS
- `aws s3 cp`: Upload files to S3
- `aws lambda create-function`: Create Lambda functions
- `aws lambda publish-layer-version`: Create Lambda layers for big dependencies
- `aws iam create-role` & `aws iam attach-role-policy`: Set up permissions
- `aws cognito-idp create-user-pool`: Create Cognito user pool
- `aws dynamodb create-table`: Create DynamoDB table
- `aws apigatewayv2 create-api`: Create API Gateway

We used these commands to automate everything and avoid manual errors.

## 7. Problems We Faced & How We Solved Them
- **IAM Permissions**: AWS is very strict about permissions. We kept getting errors like "not authorized to perform cloudformation:CreateChangeSet". We solved this by creating and attaching the right policies and using a dedicated IAM user.
- **Lambda Size Limits**: Lambda functions have strict size limits. Our code was too big because of dependencies like FAISS and numpy. We solved this by moving all big dependencies to a Lambda Layer and only uploading our code.
- **SAM Transform Errors**: IAM users sometimes can't deploy SAM templates due to missing permissions. We worked around this by deploying resources manually and using the AWS Console when needed.
- **API Gateway Integration**: Connecting Lambda functions to API Gateway can be tricky. We used the AWS Console to wire up the endpoints and triggers.
- **Cognito Client Secret Issues**: Cognito sometimes creates clients with secrets, which breaks frontend login. We made sure to set `GenerateSecret=false`.
- **Region Consistency**: We always used `ap-south-1` to avoid cross-region issues.
- **Frontend Dependency Conflicts**: React and its libraries sometimes have version conflicts. We used `--legacy-peer-deps` to fix npm install errors.

## 8. How a 10-Year-Old Can Understand This Project
Imagine you have a big book and you want to ask it questions, like "What is the capital of France?" Instead of reading the whole book, you upload it to a website. The website uses a robot (AI) to read the book for you and answer your questions. The robot is very smart and can find the answer quickly, even if the book is very big.

We built this website using tools that let us store your book, remember who you are, and let the robot answer your questions. We made sure everything is safe, fast, and doesn't cost much money.

## 9. Why This Project Is Special
- You can chat with any PDF you upload
- It uses the latest AI technology
- It's secure and respects your privacy
- It runs almost for free on AWS
- Anyone can use it, even if they're not a tech expert

## 10. What You Can Do Next
- Upload your own PDFs and chat with them
- Share the platform with friends
- Add more features (like support for images or other file types)
- Learn how cloud and AI work together

## 11. Final Thoughts
This project shows how you can use cloud, AI, and modern web tools to build something useful for everyone. We faced many challenges, but by breaking problems into small steps and using the right tools, we built a working Personal AI Knowledge Platform.

If you want to build your own, just follow the guide, use the commands, and don't be afraid to ask for help!
