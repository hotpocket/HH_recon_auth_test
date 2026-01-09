#!/bin/bash
set -e

# === CONFIGURATION ===
API_ID="mcssz9g3oc"
REGION="us-east-1"
ACCOUNT_ID="654654429054"
USER_POOL_ID="us-east-1_Te02uMsxt"
CLIENT_ID="6j2chs8duid9k1ba861hsaqlr"
FUNCTION_NAME="AuthDemoUserFunction"

echo "=== Step 1: Create IAM Role for Lambda ==="
cat > /tmp/trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "lambda.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
  --role-name LambdaAuthDemoRole \
  --assume-role-policy-document file:///tmp/trust-policy.json \
  2>/dev/null || echo "Role may already exist, continuing..."

aws iam attach-role-policy \
  --role-name LambdaAuthDemoRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
  2>/dev/null || true

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/LambdaAuthDemoRole"
echo "Role ARN: $ROLE_ARN"

# Wait for role to propagate
echo "Waiting for IAM role to propagate..."
sleep 10

echo "=== Step 2: Create Lambda Function ==="
cat > /tmp/index.mjs << 'EOF'
export const handler = async (event) => {
  console.log('Event:', JSON.stringify(event, null, 2));

  const claims = event.requestContext?.authorizer?.jwt?.claims || {};

  return {
    statusCode: 200,
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      message: "Hello from authenticated API!",
      userId: claims.sub || "unknown",
      username: claims.username || claims["cognito:username"] || "unknown",
      email: claims.email || "not in access token",
      timestamp: new Date().toISOString(),
    }),
  };
};
EOF

cd /tmp
zip -j function.zip index.mjs

# Delete existing function if it exists
aws lambda delete-function --function-name $FUNCTION_NAME 2>/dev/null || true

aws lambda create-function \
  --function-name $FUNCTION_NAME \
  --runtime nodejs20.x \
  --handler index.handler \
  --zip-file fileb://function.zip \
  --role $ROLE_ARN \
  --timeout 10

LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${FUNCTION_NAME}"
echo "Lambda ARN: $LAMBDA_ARN"

echo "=== Step 3: Enable CORS on API ==="
aws apigatewayv2 update-api \
  --api-id $API_ID \
  --cors-configuration '{
    "AllowOrigins": ["http://localhost:8080", "http://localhost:3000"],
    "AllowMethods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    "AllowHeaders": ["Authorization", "Content-Type"],
    "ExposeHeaders": ["*"],
    "MaxAge": 86400
  }'

echo "=== Step 4: Create JWT Authorizer ==="
# Delete existing authorizer if any
EXISTING_AUTH=$(aws apigatewayv2 get-authorizers --api-id $API_ID --query 'Items[?Name==`CognitoJWTAuth`].AuthorizerId' --output text)
if [ -n "$EXISTING_AUTH" ]; then
  aws apigatewayv2 delete-authorizer --api-id $API_ID --authorizer-id $EXISTING_AUTH
fi

AUTHORIZER_ID=$(aws apigatewayv2 create-authorizer \
  --api-id $API_ID \
  --authorizer-type JWT \
  --name CognitoJWTAuth \
  --identity-source '$request.header.Authorization' \
  --jwt-configuration "{
    \"Audience\": [\"$CLIENT_ID\"],
    \"Issuer\": \"https://cognito-idp.${REGION}.amazonaws.com/${USER_POOL_ID}\"
  }" \
  --query 'AuthorizerId' --output text)

echo "Authorizer ID: $AUTHORIZER_ID"

echo "=== Step 5: Create Lambda Integration ==="
INTEGRATION_ID=$(aws apigatewayv2 create-integration \
  --api-id $API_ID \
  --integration-type AWS_PROXY \
  --integration-uri $LAMBDA_ARN \
  --payload-format-version 2.0 \
  --query 'IntegrationId' --output text)

echo "Integration ID: $INTEGRATION_ID"

echo "=== Step 6: Create Route ==="
aws apigatewayv2 create-route \
  --api-id $API_ID \
  --route-key "GET /user" \
  --authorization-type JWT \
  --authorizer-id $AUTHORIZER_ID \
  --target "integrations/$INTEGRATION_ID"

echo "=== Step 7: Create/Update Stage ==="
aws apigatewayv2 create-stage \
  --api-id $API_ID \
  --stage-name '$default' \
  --auto-deploy \
  2>/dev/null || aws apigatewayv2 update-stage \
  --api-id $API_ID \
  --stage-name '$default' \
  --auto-deploy

echo "=== Step 8: Grant API Gateway Permission to Invoke Lambda ==="
aws lambda add-permission \
  --function-name $FUNCTION_NAME \
  --statement-id "apigateway-invoke-${API_ID}" \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/*" \
  2>/dev/null || echo "Permission may already exist"

echo "=== Step 9: Verify Setup ==="
echo ""
echo "Routes:"
aws apigatewayv2 get-routes --api-id $API_ID

echo ""
echo "API Endpoint:"
aws apigatewayv2 get-api --api-id $API_ID --query 'ApiEndpoint' --output text

echo ""
echo "=== DONE ==="
echo "API is ready at: https://${API_ID}.execute-api.${REGION}.amazonaws.com/user"