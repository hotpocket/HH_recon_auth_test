# AWS Authentication Demo with Flutter

A comprehensive Flutter application demonstrating AWS Cognito authentication with Google OAuth integration, featuring shell-based infrastructure management and cross-platform support.

## 🎯 Project Overview

This project serves as a practical exploration of AWS authentication patterns, focusing on:
- **AWS Cognito** user pools with Google OAuth integration
- **Shell-driven infrastructure** setup and management
- **Cross-platform Flutter** authentication flows (Web, Mobile, Desktop)
- **JWT-secured API** endpoints with Lambda functions
- **Infrastructure as Code** via bash scripts

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Flutter App   │────│  AWS API Gateway │────│ Lambda Functions│
│  (Multi-Platform)│    │   (JWT Auth)     │    │   (DynamoDB)    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                        │                        │
         │              ┌──────────────────┐               │
         └──────────────│  AWS Cognito     │───────────────┘
                        │  (Google OAuth)  │
                        └──────────────────┘
```

## 🚀 Quick Start

### Prerequisites
- AWS CLI configured with appropriate permissions
- Flutter SDK (3.0+)
- Google OAuth credentials (Client ID & Secret)
- Node.js (for Lambda functions)

### 1. Infrastructure Setup

#### Option A: Full Automated Setup
```bash
# Configure your settings in the script first
./setup_auth_infrastructure.sh
```

#### Option B: Step-by-Step Setup
```bash
# Set up just the API components
./setup_api.sh

# Set up pre-token generation Lambda
./setup_pretokengen.sh
```

### 2. Configure Google OAuth

After running setup scripts, update your Google OAuth Console:
- **Authorized JavaScript origins**: `https://[your-cognito-domain].auth.[region].amazoncognito.com`
- **Authorized redirect URIs**: `https://[your-cognito-domain].auth.[region].amazoncognito.com/oauth2/idpresponse`

### 3. Run the Flutter App

```bash
# Web (primary testing platform)
flutter run -d chrome --web-port=8080

# Mobile (iOS/Android)
flutter run

# Desktop (macOS/Windows/Linux)
flutter run -d macos  # or windows/linux
```

## 📁 Project Structure

```
auth_test/
├── lib/                          # Flutter application
│   ├── config.dart              # AWS configuration (auto-generated)
│   ├── services/                # Platform-specific auth services
│   │   ├── auth_service.dart    # Service factory
│   │   ├── auth_service_web.dart    # Web implementation
│   │   ├── auth_service_mobile.dart # Mobile implementation
│   │   └── auth_service_stub.dart   # Fallback stub
│   └── screens/
│       └── auth_screen.dart     # Main authentication UI
├── scripts/                     # Infrastructure management
│   ├── setup_auth_infrastructure.sh    # Full setup (15 steps)
│   ├── setup_api.sh                    # API-only setup
│   ├── setup_pretokengen.sh            # Pre-token Lambda setup
│   ├── teardown_auth_infrastructure.sh # Complete cleanup
│   ├── check_resources.sh              # Resource inventory
│   ├── fix_pretokengen.sh              # Lambda troubleshooting
│   └── web/
│       └── callback.html              # OAuth callback handler
└── README.md
```

## 🔧 Shell Scripts Reference

### Core Infrastructure Scripts

| Script | Purpose | Key Features |
|--------|---------|--------------|
| `setup_auth_infrastructure.sh` | Complete AWS setup | 15-step automated deployment |
| `teardown_auth_infrastructure.sh` | Complete cleanup | Removes all AWS resources |
| `check_resources.sh` | Resource inventory | Interactive AWS profile selection |
| `setup_api.sh` | API-only setup | Creates Lambda + API Gateway |
| `setup_pretokengen.sh` | Token enhancement | Adds custom claims to JWT |

### Usage Examples

```bash
# Full environment setup
./setup_auth_infrastructure.sh

# Check what resources exist
./check_resources.sh

# Clean up everything (⚠️ destructive)
./teardown_auth_infrastructure.sh

# Fix pre-token generation issues
./fix_pretokengen.sh
```

## 🔐 Authentication Flow

### Web Platform
1. User clicks "Sign in with Google"
2. Redirects to AWS Cognito hosted UI
3. Google OAuth consent screen
4. Redirect back to `callback.html`
5. Token exchange and user info retrieval
6. Automatic redirect to main app

### Mobile/Desktop Platforms
1. User clicks "Sign in with Google"
2. Opens system browser for OAuth
3. Custom URL scheme redirect (`myapp://callback`)
4. Token storage in secure storage
5. API calls with JWT authorization

## 🌐 Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| **Web** | ✅ Primary | Extensively tested, callback at `localhost:8080` |
| **iOS** | ✅ Ready | Uses custom URL scheme `myapp://callback` |
| **Android** | ✅ Ready | Uses custom URL scheme `myapp://callback` |
| **macOS** | ✅ Ready | Uses `localhost:8085` callback |
| **Windows** | ✅ Ready | Uses `localhost:8085` callback |
| **Linux** | ✅ Ready | Uses `localhost:8085` callback |

## 🔍 Key AWS Resources Created

### Cognito
- **User Pool**: Managed user directory with Google federation
- **Identity Provider**: Google OAuth integration
- **App Client**: OAuth2 client configuration
- **Pre-token Lambda**: Custom claims injection

### API Gateway
- **HTTP API**: RESTful endpoints with JWT authorization
- **Authorizer**: Cognito JWT token validation
- **Routes**: `/user` (GET/PUT), `/health` (public)
- **CORS**: Configured for local development

### Lambda Functions
- **API Handler**: User profile management with DynamoDB
- **Pre-token Generator**: Custom JWT claims enhancement
- **IAM Roles**: Least-privilege access policies

### DynamoDB
- **Users Table**: User profile storage with `userId` as primary key
- **Auto-scaling**: Pay-per-request billing mode

## 🧪 Testing

### API Testing
```bash
# Health check (public)
curl https://[api-id].execute-api.[region].amazonaws.com/health

# Authenticated endpoint (requires JWT)
curl -H "Authorization: Bearer [jwt-token]" \
     https://[api-id].execute-api.[region].amazoncognito.com/user
```

### Flutter Testing
```bash
# Run tests
flutter test

# Web testing with specific port
flutter run -d chrome --web-port=8080

# Mobile testing
flutter run -d ios
flutter run -d android
```

## 📊 Monitoring & Debugging

### CloudWatch Logs
- **Lambda Logs**: `/aws/lambda/[function-name]`
- **API Gateway Logs**: Access and execution logs
- **Cognito Logs**: User authentication events

### Local Debugging
```bash
# Check AWS resources
./check_resources.sh

# View Lambda logs
aws logs tail /aws/lambda/MyAppApiHandler --follow

# Test API endpoints
curl -v https://[api-endpoint]/health
```

## 🛡️ Security Features

- **JWT Token Validation**: All API endpoints secured with Cognito JWT
- **HTTPS Only**: All communications encrypted
- **CORS Configuration**: Restricted to specific origins
- **Least Privilege IAM**: Minimal AWS permissions
- **Secure Token Storage**: Platform-specific secure storage

## 💰 Cost Considerations

### AWS Free Tier Eligible
- **Cognito**: 50,000 monthly active users
- **Lambda**: 1M requests + 400,000 GB-seconds
- **API Gateway**: 1M API calls
- **DynamoDB**: 25 GB storage + 200M requests

### Estimated Monthly Cost (Low Usage)
- **Cognito**: $0 (within free tier)
- **Lambda**: $0-2 (depending on usage)
- **API Gateway**: $0-3 (depending on calls)
- **DynamoDB**: $0-1 (depending on storage)

## 🔄 Development Workflow

1. **Setup**: Run `./setup_auth_infrastructure.sh`
2. **Develop**: Make changes to Flutter app or Lambda functions
3. **Test**: Use `./check_resources.sh` to verify setup
4. **Debug**: Check CloudWatch logs for issues
5. **Cleanup**: Run `./teardown_auth_infrastructure.sh` when done

## 📝 Configuration Files

### Auto-generated Files
- `auth_config_output.json`: Complete AWS resource configuration
- `flutter_config.dart`: Flutter app configuration (copy to `lib/config.dart`)

### Manual Configuration
- Update `lib/config.dart` with your specific values
- Configure Google OAuth console with redirect URLs
- Set up AWS CLI with appropriate permissions

## 🆘 Troubleshooting

### Common Issues

**"User Pool not found"**
- Check AWS region configuration
- Verify `USER_POOL_ID` in config files

**"Lambda permission denied"**
- Wait 10-15 seconds after IAM role creation
- Run `./fix_pretokengen.sh` for pre-token issues

**"CORS errors"**
- Verify callback URLs in Cognito app client
- Check CORS configuration in API Gateway

**"Google OAuth redirect mismatch"**
- Update Google OAuth console with correct redirect URLs
- Ensure Cognito domain matches configuration

## 🤝 Contributing

This is an exploration project focused on AWS authentication patterns. Contributions welcome for:
- Additional platform support
- Enhanced shell scripts
- Security improvements
- Documentation updates

## 📄 License

This project is provided as-is for educational and exploration purposes.

---

**Note**: This project is primarily focused on exploring AWS authentication patterns and shell-based infrastructure management. The Flutter app has been tested extensively on web due to platform priority uncertainty, but all mobile platforms are supported and ready for testing.
