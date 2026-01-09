#!/bin/bash
set -e

REGION="us-east-1"
ACCOUNT_ID="654654429054"
USER_POOL_ID="us-east-1_Te02uMsxt"
FUNCTION_NAME="CognitoPreTokenGenerator"

echo "=== Create Pre-Token Generation Lambda ==="
cat > /tmp/pretokengen.mjs << 'EOF'
export const handler = async (event) => {
  // Add custom claims to the access token
  event.response = {
    claimsOverrideDetails: {
      claimsToAddOrOverride: {
        email: event.request.userAttributes.email || "",
        name: event.request.userAttributes.name || "",
        picture: event.request.userAttributes.picture || "",
      },
    },
  };

  return event;
};
EOF

cd /tmp
zip -j pretokengen.zip pretokengen.mjs

# Create role if needed
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
  --role-name CognitoPreTokenGenRole \
  --assume-role-policy-document file:///tmp/trust-policy.json \
  2>/dev/null || echo "Role exists"

aws iam attach-role-policy \
  --role-name CognitoPreTokenGenRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
  2>/dev/null || true

sleep 10

# Delete and recreate function
aws lambda delete-function --function-name $FUNCTION_NAME 2>/dev/null || true

aws lambda create-function \
  --function-name $FUNCTION_NAME \
  --runtime nodejs20.x \
  --handler pretokengen.handler \
  --zip-file fileb://pretokengen.zip \
  --role "arn:aws:iam::${ACCOUNT_ID}:role/CognitoPreTokenGenRole" \
  --timeout 5

# Grant Cognito permission to invoke Lambda
aws lambda add-permission \
  --function-name $FUNCTION_NAME \
  --statement-id cognito-invoke \
  --action lambda:InvokeFunction \
  --principal cognito-idp.amazonaws.com \
  --source-arn "arn:aws:cognito-idp:${REGION}:${ACCOUNT_ID}:userpool/${USER_POOL_ID}"

echo "=== Attach Trigger to Cognito ==="
LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${FUNCTION_NAME}"

aws cognito-idp update-user-pool \
  --user-pool-id $USER_POOL_ID \
  --lambda-config "{
    \"PreTokenGenerationConfig\": {
      \"LambdaVersion\": \"V2_0\",
      \"LambdaArn\": \"$LAMBDA_ARN\"
    }
  }"

echo "=== Done ==="
echo "Sign out and sign back in to get a new token with email claim"