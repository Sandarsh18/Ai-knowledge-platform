# Personal AI Knowledge Platform (RAG-based)

A serverless Personal AI Knowledge Platform that allows users to upload PDF documents and ask questions about them using AI-powered Retrieval Augmented Generation (RAG).

## 🚀 Features
- **PDF Upload**: Upload and process PDF documents
- **AI-Powered Q&A**: Ask questions about your documents using Gemini AI
- **Vector Search**: FAISS-powered semantic search for relevant content
- **Secure Authentication**: AWS Cognito user management
- **Auto-Correction**: Intelligent document ID mismatch detection and correction
- **Modern UI**: Responsive React frontend with real-time chat interface

## 🏗️ Architecture

```
React Frontend → API Gateway → Lambda Functions → DynamoDB + S3
                                      ↓
                               Gemini AI API + FAISS
```

### Technologies Used
- **Backend**: Python 3.13 AWS Lambda
- **API**: AWS API Gateway HTTP API  
- **Storage**: Amazon S3 (PDFs) + DynamoDB (metadata & embeddings)
- **Authentication**: AWS Cognito (no client secret)
- **AI**: Google Gemini 1.5 Flash API
- **Vector Search**: FAISS (Lambda Layer)
- **Frontend**: React with modern UI/UX

## 📋 Prerequisites
- AWS CLI configured with appropriate permissions
- Node.js 18+ and npm
- Python 3.13+
- AWS SAM CLI
- Google AI Studio API key for Gemini

## 🛠️ Setup Instructions

### 1. Clone and Configure
```bash
git clone https://github.com/Sandarsh18/Ai-knowledge-platform.git
cd Ai-knowledge-platform

# Copy environment templates
cp frontend/.env.example frontend/.env
cp backend/.env.example backend/.env.local
```

### 2. Configure Environment Variables

**Frontend (.env):**
```bash
REACT_APP_API_URL=https://your-api-gateway-url.execute-api.region.amazonaws.com
REACT_APP_COGNITO_USER_POOL_ID=your-region_YourPoolId
REACT_APP_COGNITO_USER_POOL_CLIENT_ID=your-client-id
REACT_APP_COGNITO_REGION=your-region
```

**Backend (AWS Lambda Environment):**
- `DYNAMODB_TABLE`: pai-embeddings-metadata
- `S3_BUCKET`: pai-pdf-storage
- `GEMINI_API_KEY`: Your Gemini API key (store in AWS Secrets Manager)
- `REGION`: ap-south-1

### 3. Deploy Infrastructure
```bash
# Deploy with AWS SAM
cd infra
sam build
sam deploy --guided
```

### 4. Build and Deploy Frontend
```bash
cd frontend
npm install
npm run build
# Deploy build folder to your hosting service
```

## 🔧 Key Features

### Auto-Correction System
The platform includes an intelligent doc ID mismatch detection and correction system:
- **Automatic Detection**: Identifies when document IDs don't match
- **Seamless Correction**: Applies known mappings transparently
- **User Notification**: Informs users when corrections are applied
- **Dual Protection**: Both client-side and server-side validation

### Error Handling
- Comprehensive retry logic with exponential backoff
- Quota exceeded fallback responses
- User-friendly error messages
- Structured error logging

### Security Features
- AWS Cognito authentication
- IAM least-privilege permissions
- CORS properly configured
- Secrets stored in AWS Secrets Manager

## 📚 Documentation
- [Deployment Guide](DEPLOYMENT-GUIDE.md)
- [Doc ID Auto-Correction System](DOC-ID-AUTO-CORRECTION.md)
- [Project Story](PROJECT-STORY.md)

## 🤝 Contributing
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License
This project is licensed under the MIT License.

## 🚨 Important Notes
- Never commit sensitive data (API keys, credentials)
- Use AWS Secrets Manager for production API keys
- Follow AWS free tier limits to avoid charges
- Test thoroughly before deploying to production
