#!/bin/bash
set -e

###############################################################################
# CONFIGURATION - Update these values before running
###############################################################################

# AWS Configuration
AWS_REGION="us-east-1"
AWS_PROFILE=""  # Leave empty for default profile, or set to your profile name

# Cognito Configuration
USER_POOL_NAME="MyApp"
COGNITO_DOMAIN_PREFIX="myapp-auth-$(date +%s)"  # Must be globally unique

# Google OAuth Configuration (from https://console.cloud.google.com/apis/credentials)
GOOGLE_CLIENT_ID="your-google-client-id.apps.googleusercontent.com"
GOOGLE_CLIENT_SECRET="your-google-client-secret"

# App Configuration
APP_NAME="MyApp"
CALLBACK_URLS='["myapp://callback","http://localhost:8080/callback.html","http://localhost:8085/callback"]'
LOGOUT_URLS='["myapp://signout","http://localhost:8080","http://localhost:8085"]'

# DynamoDB Configuration
DYNAMODB_TABLE_NAME="Users"

###############################################################################
# SCRIPT - Do not modify below unless you know what you're doing
###############################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# AWS CLI profile flag
PROFILE_FLAG=""
if [ -n "$AWS_PROFILE" ]; then
  PROFILE_FLAG="--profile $AWS_PROFILE"
fi

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

get_account_id() {
  aws sts get-caller-identity $PROFILE_FLAG --query 'Account' --output text
}

# Output file for configuration values
OUTPUT_FILE="auth_config_output.json"

###############################################################################
# VALIDATION
###############################################################################

log_info "Validating configuration..."

if [ "$GOOGLE_CLIENT_ID" = "your-google-client-id.apps.googleusercontent.com" ]; then
  log_error "Please update GOOGLE_CLIENT_ID in the script configuration"
  exit 1
fi

if [ "$GOOGLE_CLIENT_SECRET" = "your-google-client-secret" ]; then
  log_error "Please update GOOGLE_CLIENT_SECRET in the script configuration"
  exit 1
fi

# Get AWS Account ID
ACCOUNT_ID=$(get_account_id)
log_info "AWS Account ID: $ACCOUNT_ID"
log_info "AWS Region: $AWS_REGION"

###############################################################################
# STEP 1: Create Cognito User Pool
###############################################################################

log_info "Step 1: Creating Cognito User Pool..."

USER_POOL_ID=$(aws cognito-idp create-user-pool \
  $PROFILE_FLAG \
  --pool-name "$USER_POOL_NAME" \
  --policies 'PasswordPolicy={MinimumLength=8,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true,RequireSymbols=false}' \
  --auto-verified-attributes email \
  --schema '[{"Name":"email","Required":true,"Mutable":true}]' \
  --query 'UserPool.Id' \
  --output text \
  --region $AWS_REGION)

log_success "User Pool created: $USER_POOL_ID"

###############################################################################
# STEP 2: Create Cognito Domain
###############################################################################

log_info "Step 2: Creating Cognito Domain..."

aws cognito-idp create-user-pool-domain \
  $PROFILE_FLAG \
  --user-pool-id $USER_POOL_ID \
  --domain $COGNITO_DOMAIN_PREFIX \
  --region $AWS_REGION

COGNITO_DOMAIN="${COGNITO_DOMAIN_PREFIX}.auth.${AWS_REGION}.amazoncognito.com"
log_success "Cognito Domain created: https://$COGNITO_DOMAIN"

###############################################################################
# STEP 3: Create Google Identity Provider
###############################################################################

log_info "Step 3: Creating Google Identity Provider..."

aws cognito-idp create-identity-provider \
  $PROFILE_FLAG \
  --user-pool-id $USER_POOL_ID \
  --provider-name Google \
  --provider-type Google \
  --provider-details "{
    \"client_id\": \"$GOOGLE_CLIENT_ID\",
    \"client_secret\": \"$GOOGLE_CLIENT_SECRET\",
    \"authorize_scopes\": \"openid email profile\"
  }" \
  --attribute-mapping '{
    "email": "email",
    "name": "name",
    "picture": "picture",
    "username": "sub"
  }' \
  --region $AWS_REGION

log_success "Google Identity Provider created with attribute mapping"

###############################################################################
# STEP 4: Create User Pool Client
###############################################################################

log_info "Step 4: Creating User Pool Client..."

CLIENT_ID=$(aws cognito-idp create-user-pool-client \
  $PROFILE_FLAG \
  --user-pool-id $USER_POOL_ID \
  --client-name "${APP_NAME}Client" \
  --explicit-auth-flows ALLOW_USER_SRP_AUTH ALLOW_REFRESH_TOKEN_AUTH \
  --allowed-o-auth-flows code \
  --allowed-o-auth-scopes openid email profile \
  --supported-identity-providers Google \
  --callback-urls "$CALLBACK_URLS" \
  --logout-urls "$LOGOUT_URLS" \
  --allowed-o-auth-flows-user-pool-client \
  --query 'UserPoolClient.ClientId' \
  --output text \
  --region $AWS_REGION)

log_success "User Pool Client created: $CLIENT_ID"

###############################################################################
# STEP 5: Create IAM Roles
###############################################################################

log_info "Step 5: Creating IAM Roles..."

# Trust policy for Lambda
cat > /tmp/lambda-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "lambda.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

# Create Lambda execution role
aws iam create-role \
  $PROFILE_FLAG \
  --role-name "${APP_NAME}LambdaRole" \
  --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
  2>/dev/null || log_warn "Lambda role may already exist, continuing..."

aws iam attach-role-policy \
  $PROFILE_FLAG \
  --role-name "${APP_NAME}LambdaRole" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
  2>/dev/null || true

aws iam attach-role-policy \
  $PROFILE_FLAG \
  --role-name "${APP_NAME}LambdaRole" \
  --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess \
  2>/dev/null || true

LAMBDA_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${APP_NAME}LambdaRole"

# Create Pre-Token Generation role
aws iam create-role \
  $PROFILE_FLAG \
  --role-name "${APP_NAME}PreTokenGenRole" \
  --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
  2>/dev/null || log_warn "PreTokenGen role may already exist, continuing..."

aws iam attach-role-policy \
  $PROFILE_FLAG \
  --role-name "${APP_NAME}PreTokenGenRole" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
  2>/dev/null || true

PRETOKEN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${APP_NAME}PreTokenGenRole"

log_success "IAM Roles created"
log_info "Waiting 10 seconds for IAM role propagation..."
sleep 10

###############################################################################
# STEP 6: Create Pre-Token Generation Lambda
###############################################################################

log_info "Step 6: Creating Pre-Token Generation Lambda..."

cat > /tmp/pretokengen.mjs << 'EOF'
export const handler = async (event) => {
  console.log('Event:', JSON.stringify(event, null, 2));

  const userAttributes = event.request.userAttributes || {};

  event.response = {
    claimsAndScopeOverrideDetails: {
      accessTokenGeneration: {
        claimsToAddOrOverride: {
          email: userAttributes.email || "",
          name: userAttributes.name || "",
          picture: userAttributes.picture || "",
        },
      },
      idTokenGeneration: {
        claimsToAddOrOverride: {
          email: userAttributes.email || "",
          name: userAttributes.name || "",
          picture: userAttributes.picture || "",
        },
      },
    },
  };

  console.log('Response:', JSON.stringify(event.response, null, 2));
  return event;
};
EOF

cd /tmp
zip -j pretokengen.zip pretokengen.mjs

PRETOKEN_FUNCTION_NAME="${APP_NAME}PreTokenGenerator"

aws lambda create-function \
  $PROFILE_FLAG \
  --function-name $PRETOKEN_FUNCTION_NAME \
  --runtime nodejs20.x \
  --handler pretokengen.handler \
  --zip-file fileb://pretokengen.zip \
  --role $PRETOKEN_ROLE_ARN \
  --timeout 5 \
  --region $AWS_REGION

PRETOKEN_LAMBDA_ARN="arn:aws:lambda:${AWS_REGION}:${ACCOUNT_ID}:function:${PRETOKEN_FUNCTION_NAME}"

# Grant Cognito permission to invoke
aws lambda add-permission \
  $PROFILE_FLAG \
  --function-name $PRETOKEN_FUNCTION_NAME \
  --statement-id cognito-invoke \
  --action lambda:InvokeFunction \
  --principal cognito-idp.amazonaws.com \
  --source-arn "arn:aws:cognito-idp:${AWS_REGION}:${ACCOUNT_ID}:userpool/${USER_POOL_ID}" \
  --region $AWS_REGION

# Attach trigger to Cognito
aws cognito-idp update-user-pool \
  $PROFILE_FLAG \
  --user-pool-id $USER_POOL_ID \
  --lambda-config "{
    \"PreTokenGenerationConfig\": {
      \"LambdaVersion\": \"V2_0\",
      \"LambdaArn\": \"$PRETOKEN_LAMBDA_ARN\"
    }
  }" \
  --region $AWS_REGION

log_success "Pre-Token Generation Lambda created and attached"

###############################################################################
# STEP 7: Create DynamoDB Table
###############################################################################

log_info "Step 7: Creating DynamoDB Table..."

aws dynamodb create-table \
  $PROFILE_FLAG \
  --table-name $DYNAMODB_TABLE_NAME \
  --attribute-definitions AttributeName=userId,AttributeType=S \
  --key-schema AttributeName=userId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $AWS_REGION \
  2>/dev/null || log_warn "DynamoDB table may already exist, continuing..."

log_success "DynamoDB Table created: $DYNAMODB_TABLE_NAME"

###############################################################################
# STEP 8: Create API Lambda Function
###############################################################################

log_info "Step 8: Creating API Lambda Function..."

cat > /tmp/api-handler.mjs << 'EOF'
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, PutCommand } from "@aws-sdk/lib-dynamodb";

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);
const TABLE_NAME = process.env.TABLE_NAME || "Users";

export const handler = async (event) => {
  console.log('Event:', JSON.stringify(event, null, 2));

  const claims = event.requestContext?.authorizer?.jwt?.claims || {};
  const method = event.requestContext?.http?.method || event.httpMethod;
  const path = event.requestContext?.http?.path || event.path;

  const userId = claims.sub;
  const email = claims.email || null;
  const name = claims.name || null;
  const picture = claims.picture || null;

  try {
    // GET /user - Get or create user profile
    if (method === 'GET' && path === '/user') {
      // Try to get existing user
      const getResult = await docClient.send(new GetCommand({
        TableName: TABLE_NAME,
        Key: { userId },
      }));

      if (getResult.Item) {
        return response(200, {
          message: "User found",
          user: getResult.Item,
        });
      }

      // Create new user if not exists
      const newUser = {
        userId,
        email,
        name,
        picture,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      };

      await docClient.send(new PutCommand({
        TableName: TABLE_NAME,
        Item: newUser,
      }));

      return response(201, {
        message: "User created",
        user: newUser,
      });
    }

    // PUT /user - Update user profile
    if (method === 'PUT' && path === '/user') {
      const body = JSON.parse(event.body || '{}');

      const updatedUser = {
        userId,
        email: email || body.email,
        name: body.name || name,
        picture: picture,
        bio: body.bio || null,
        updatedAt: new Date().toISOString(),
      };

      await docClient.send(new PutCommand({
        TableName: TABLE_NAME,
        Item: updatedUser,
      }));

      return response(200, {
        message: "User updated",
        user: updatedUser,
      });
    }

    // Health check
    if (method === 'GET' && path === '/health') {
      return response(200, {
        status: "healthy",
        timestamp: new Date().toISOString(),
      });
    }

    return response(404, { message: "Not found" });

  } catch (error) {
    console.error('Error:', error);
    return response(500, {
      message: "Internal server error",
      error: error.message,
    });
  }
};

function response(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}
EOF

cd /tmp
zip -j api-handler.zip api-handler.mjs

API_FUNCTION_NAME="${APP_NAME}ApiHandler"

aws lambda create-function \
  $PROFILE_FLAG \
  --function-name $API_FUNCTION_NAME \
  --runtime nodejs20.x \
  --handler api-handler.handler \
  --zip-file fileb://api-handler.zip \
  --role $LAMBDA_ROLE_ARN \
  --timeout 10 \
  --environment "Variables={TABLE_NAME=$DYNAMODB_TABLE_NAME}" \
  --region $AWS_REGION

API_LAMBDA_ARN="arn:aws:lambda:${AWS_REGION}:${ACCOUNT_ID}:function:${API_FUNCTION_NAME}"

log_success "API Lambda Function created: $API_FUNCTION_NAME"

###############################################################################
# STEP 9: Create HTTP API Gateway
###############################################################################

log_info "Step 9: Creating HTTP API Gateway..."

API_ID=$(aws apigatewayv2 create-api \
  $PROFILE_FLAG \
  --name "${APP_NAME}API" \
  --protocol-type HTTP \
  --cors-configuration '{
    "AllowOrigins": ["http://localhost:8080", "http://localhost:3000", "http://localhost:8085"],
    "AllowMethods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    "AllowHeaders": ["Authorization", "Content-Type"],
    "ExposeHeaders": ["*"],
    "MaxAge": 86400
  }' \
  --query 'ApiId' \
  --output text \
  --region $AWS_REGION)

API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com"

log_success "API Gateway created: $API_ID"
log_success "API Endpoint: $API_ENDPOINT"

###############################################################################
# STEP 10: Create JWT Authorizer
###############################################################################

log_info "Step 10: Creating JWT Authorizer..."

AUTHORIZER_ID=$(aws apigatewayv2 create-authorizer \
  $PROFILE_FLAG \
  --api-id $API_ID \
  --authorizer-type JWT \
  --name CognitoJWTAuth \
  --identity-source '$request.header.Authorization' \
  --jwt-configuration "{
    \"Audience\": [\"$CLIENT_ID\"],
    \"Issuer\": \"https://cognito-idp.${AWS_REGION}.amazonaws.com/${USER_POOL_ID}\"
  }" \
  --query 'AuthorizerId' \
  --output text \
  --region $AWS_REGION)

log_success "JWT Authorizer created: $AUTHORIZER_ID"

###############################################################################
# STEP 11: Create Lambda Integration
###############################################################################

log_info "Step 11: Creating Lambda Integration..."

INTEGRATION_ID=$(aws apigatewayv2 create-integration \
  $PROFILE_FLAG \
  --api-id $API_ID \
  --integration-type AWS_PROXY \
  --integration-uri $API_LAMBDA_ARN \
  --payload-format-version 2.0 \
  --query 'IntegrationId' \
  --output text \
  --region $AWS_REGION)

log_success "Lambda Integration created: $INTEGRATION_ID"

###############################################################################
# STEP 12: Create Routes
###############################################################################

log_info "Step 12: Creating Routes..."

# GET /user (authenticated)
aws apigatewayv2 create-route \
  $PROFILE_FLAG \
  --api-id $API_ID \
  --route-key "GET /user" \
  --authorization-type JWT \
  --authorizer-id $AUTHORIZER_ID \
  --target "integrations/$INTEGRATION_ID" \
  --region $AWS_REGION

# PUT /user (authenticated)
aws apigatewayv2 create-route \
  $PROFILE_FLAG \
  --api-id $API_ID \
  --route-key "PUT /user" \
  --authorization-type JWT \
  --authorizer-id $AUTHORIZER_ID \
  --target "integrations/$INTEGRATION_ID" \
  --region $AWS_REGION

# GET /health (public)
aws apigatewayv2 create-route \
  $PROFILE_FLAG \
  --api-id $API_ID \
  --route-key "GET /health" \
  --target "integrations/$INTEGRATION_ID" \
  --region $AWS_REGION

log_success "Routes created: GET /user, PUT /user, GET /health"

###############################################################################
# STEP 13: Create Stage with Auto-Deploy
###############################################################################

log_info "Step 13: Creating Stage..."

aws apigatewayv2 create-stage \
  $PROFILE_FLAG \
  --api-id $API_ID \
  --stage-name '$default' \
  --auto-deploy \
  --region $AWS_REGION

log_success "Stage created with auto-deploy"

###############################################################################
# STEP 14: Grant API Gateway Permission to Invoke Lambda
###############################################################################

log_info "Step 14: Granting API Gateway Lambda permissions..."

aws lambda add-permission \
  $PROFILE_FLAG \
  --function-name $API_FUNCTION_NAME \
  --statement-id "apigateway-invoke-${API_ID}" \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${AWS_REGION}:${ACCOUNT_ID}:${API_ID}/*/*" \
  --region $AWS_REGION

log_success "Lambda permissions granted"

###############################################################################
# STEP 15: Generate Configuration Output
###############################################################################

log_info "Step 15: Generating configuration output..."

cat > $OUTPUT_FILE << EOF
{
  "aws": {
    "region": "$AWS_REGION",
    "accountId": "$ACCOUNT_ID"
  },
  "cognito": {
    "userPoolId": "$USER_POOL_ID",
    "clientId": "$CLIENT_ID",
    "domain": "$COGNITO_DOMAIN"
  },
  "api": {
    "id": "$API_ID",
    "endpoint": "$API_ENDPOINT"
  },
  "dynamodb": {
    "tableName": "$DYNAMODB_TABLE_NAME"
  },
  "lambda": {
    "apiHandler": "$API_FUNCTION_NAME",
    "preTokenGenerator": "$PRETOKEN_FUNCTION_NAME"
  }
}
EOF

log_success "Configuration saved to $OUTPUT_FILE"

###############################################################################
# STEP 16: Generate Flutter config.dart
###############################################################################

FLUTTER_CONFIG_FILE="flutter_config.dart"

cat > $FLUTTER_CONFIG_FILE << EOF
class AuthConfig {
  static const String cognitoDomain = '$COGNITO_DOMAIN';
  static const String userPoolId = '$USER_POOL_ID';
  static const String clientId = '$CLIENT_ID';
  static const String apiEndpoint = '$API_ENDPOINT';

  static const String mobileRedirectUri = 'myapp://callback';
  static const String webRedirectUri = 'http://localhost:8080/callback.html';
  static const String desktopRedirectUri = 'http://localhost:8085/callback';

  static const String mobileLogoutUri = 'myapp://signout';
  static const String webLogoutUri = 'http://localhost:8080';

  static const List<String> scopes = ['openid', 'email', 'profile'];
}
EOF

log_success "Flutter config saved to $FLUTTER_CONFIG_FILE"

###############################################################################
# SUMMARY
###############################################################################

echo ""
echo "=============================================================================="
echo -e "${GREEN}SETUP COMPLETE${NC}"
echo "=============================================================================="
echo ""
echo "Cognito User Pool ID:  $USER_POOL_ID"
echo "Cognito Client ID:     $CLIENT_ID"
echo "Cognito Domain:        https://$COGNITO_DOMAIN"
echo ""
echo "API Gateway ID:        $API_ID"
echo "API Endpoint:          $API_ENDPOINT"
echo ""
echo "DynamoDB Table:        $DYNAMODB_TABLE_NAME"
echo ""
echo "=============================================================================="
echo -e "${YELLOW}NEXT STEPS${NC}"
echo "=============================================================================="
echo ""
echo "1. Update Google OAuth Console:"
echo "   - Authorized JavaScript origins: https://$COGNITO_DOMAIN"
echo "   - Authorized redirect URIs: https://$COGNITO_DOMAIN/oauth2/idpresponse"
echo ""
echo "2. Copy $FLUTTER_CONFIG_FILE to your Flutter project:"
echo "   cp $FLUTTER_CONFIG_FILE lib/config.dart"
echo ""
echo "3. Run your Flutter app:"
echo "   flutter run -d chrome --web-port=8080"
echo ""
echo "4. Test the API:"
echo "   curl $API_ENDPOINT/health"
echo ""
echo "=============================================================================="

# Cleanup temp files
rm -f /tmp/lambda-trust-policy.json
rm -f /tmp/pretokengen.mjs
rm -f /tmp/pretokengen.zip
rm -f /tmp/api-handler.mjs
rm -f /tmp/api-handler.zip

log_success "Temporary files cleaned up"