#!/bin/bash
set -e

###############################################################################
# CONFIGURATION - Must match setup script
###############################################################################

AWS_REGION="us-east-1"
AWS_PROFILE=""
APP_NAME="MyApp"
DYNAMODB_TABLE_NAME="Users"

# Load from output file if exists
if [ -f "auth_config_output.json" ]; then
  USER_POOL_ID=$(jq -r '.cognito.userPoolId' auth_config_output.json)
  API_ID=$(jq -r '.api.id' auth_config_output.json)
  echo "Loaded configuration from auth_config_output.json"
else
  echo "No auth_config_output.json found. Please provide values:"
  read -p "User Pool ID: " USER_POOL_ID
  read -p "API Gateway ID: " API_ID
fi

PROFILE_FLAG=""
if [ -n "$AWS_PROFILE" ]; then
  PROFILE_FLAG="--profile $AWS_PROFILE"
fi

ACCOUNT_ID=$(aws sts get-caller-identity $PROFILE_FLAG --query 'Account' --output text)

###############################################################################
# TEARDOWN
###############################################################################

echo "WARNING: This will delete all resources for $APP_NAME"
read -p "Are you sure? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted"
  exit 1
fi

echo "Deleting API Gateway..."
aws apigatewayv2 delete-api $PROFILE_FLAG --api-id $API_ID --region $AWS_REGION 2>/dev/null || true

echo "Deleting Lambda functions..."
aws lambda delete-function $PROFILE_FLAG --function-name "${APP_NAME}ApiHandler" --region $AWS_REGION 2>/dev/null || true
aws lambda delete-function $PROFILE_FLAG --function-name "${APP_NAME}PreTokenGenerator" --region $AWS_REGION 2>/dev/null || true

echo "Deleting Cognito User Pool..."
aws cognito-idp delete-user-pool $PROFILE_FLAG --user-pool-id $USER_POOL_ID --region $AWS_REGION 2>/dev/null || true

echo "Deleting DynamoDB table..."
aws dynamodb delete-table $PROFILE_FLAG --table-name $DYNAMODB_TABLE_NAME --region $AWS_REGION 2>/dev/null || true

echo "Deleting IAM roles..."
aws iam detach-role-policy $PROFILE_FLAG --role-name "${APP_NAME}LambdaRole" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
aws iam detach-role-policy $PROFILE_FLAG --role-name "${APP_NAME}LambdaRole" --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess 2>/dev/null || true
aws iam delete-role $PROFILE_FLAG --role-name "${APP_NAME}LambdaRole" 2>/dev/null || true

aws iam detach-role-policy $PROFILE_FLAG --role-name "${APP_NAME}PreTokenGenRole" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
aws iam delete-role $PROFILE_FLAG --role-name "${APP_NAME}PreTokenGenRole" 2>/dev/null || true

echo "Cleaning up local files..."
rm -f auth_config_output.json flutter_config.dart

echo "Teardown complete!"