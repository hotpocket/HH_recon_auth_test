#!/bin/bash
set -e

REGION="us-east-1"
ACCOUNT_ID="654654429054"
USER_POOL_ID="us-east-1_Te02uMsxt"
FUNCTION_NAME="CognitoPreTokenGenerator"

echo "=== Update Pre-Token Generation Lambda (V2_0 format) ==="
cat > /tmp/pretokengen.mjs << 'EOF'
export const handler = async (event) => {
  console.log('Event:', JSON.stringify(event, null, 2));

  const userAttributes = event.request.userAttributes || {};

  // V2_0 format uses claimsAndScopeOverrideDetails
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

aws lambda update-function-code \
  --function-name $FUNCTION_NAME \
  --zip-file fileb://pretokengen.zip

echo "=== Lambda updated ==="