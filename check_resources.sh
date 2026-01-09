#!/bin/bash

###############################################################################
# AWS Resource Inventory Script
###############################################################################

AWS_REGION="us-east-1"

# Function to list and select AWS profile
select_aws_profile() {
  local config_file="$HOME/.aws/config"
  local profiles=()
  local i=1

  echo "Available AWS Profiles:"
  echo "0) [Default - no profile]"

  if [ -f "$config_file" ]; then
    # Extract profile names from config file
    while IFS= read -r line; do
      if [[ "$line" =~ ^\[profile\ (.+)\] ]]; then
        profiles+=("${BASH_REMATCH[1]}")
      elif [[ "$line" =~ ^\[([^]]+)\] ]] && [[ "${BASH_REMATCH[1]}" != "default" ]]; then
        profiles+=("${BASH_REMATCH[1]}")
      fi
    done < "$config_file"

    # Display profiles if any were found
    if [ ${#profiles[@]} -gt 0 ]; then
      for profile in "${profiles[@]}"; do
        echo "$i) $profile"
        ((i++))
      done
    fi
  fi

  read -p "Select profile (0-$i): " selection

  # Handle selection with validation
  if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
    #echo "Invalid input, using default"
    AWS_PROFILE=""
  elif [ "$selection" -eq 0 ]; then
    AWS_PROFILE=""
  elif [ "$selection" -ge 1 ] && [ "$selection" -lt "$i" ]; then
    AWS_PROFILE="${profiles[$((selection-1))]}"
  else
    #echo "Invalid selection, using default"
    AWS_PROFILE=""
  fi

  # Confirm selection
  if [ -n "$AWS_PROFILE" ]; then
    echo "Using profile: $AWS_PROFILE"
  else
    echo "Using default profile"
  fi
  echo ""
}

# Prompt the user for a profile to run this script with
select_aws_profile

PROFILE_FLAG=""
if [ -n "$AWS_PROFILE" ]; then
  PROFILE_FLAG="--profile $AWS_PROFILE"
fi

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_header() {
  echo ""
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  $1${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════════${NC}"
}

print_subheader() {
  echo -e "${YELLOW}  $1${NC}"
}

###############################################################################
# Account Info
###############################################################################

print_header "AWS ACCOUNT INFO"
ACCOUNT_ID=$(aws sts get-caller-identity $PROFILE_FLAG --query 'Account' --output text 2>/dev/null)
CALLER_ARN=$(aws sts get-caller-identity $PROFILE_FLAG --query 'Arn' --output text 2>/dev/null)
echo "  Account ID: $ACCOUNT_ID"
echo "  Caller ARN: $CALLER_ARN"
echo "  Region:     $AWS_REGION"

###############################################################################
# S3 Buckets
###############################################################################

print_header "S3 BUCKETS"
BUCKETS=$(aws s3api list-buckets $PROFILE_FLAG --query 'Buckets[*].[Name,CreationDate]' --output text 2>/dev/null)
if [ -z "$BUCKETS" ]; then
  echo "  No buckets found"
else
  echo "$BUCKETS" | while read -r name date; do
    echo "  • $name (created: $date)"
  done
fi

###############################################################################
# Cognito User Pools
###############################################################################

print_header "COGNITO USER POOLS"
POOLS=$(aws cognito-idp list-user-pools $PROFILE_FLAG --max-results 60 --region $AWS_REGION --query 'UserPools[*].[Id,Name]' --output text 2>/dev/null)
if [ -z "$POOLS" ]; then
  echo "  No user pools found"
else
  echo "$POOLS" | while read -r id name; do
    echo "  • $name"
    echo "    ID: $id"

    # List clients for this pool
    CLIENTS=$(aws cognito-idp list-user-pool-clients $PROFILE_FLAG --user-pool-id "$id" --region $AWS_REGION --query 'UserPoolClients[*].[ClientId,ClientName]' --output text 2>/dev/null)
    if [ -n "$CLIENTS" ]; then
      print_subheader "Clients:"
      echo "$CLIENTS" | while read -r cid cname; do
        echo "      - $cname ($cid)"
      done
    fi

    # List identity providers
    PROVIDERS=$(aws cognito-idp list-identity-providers $PROFILE_FLAG --user-pool-id "$id" --region $AWS_REGION --query 'Providers[*].ProviderName' --output text 2>/dev/null)
    if [ -n "$PROVIDERS" ]; then
      print_subheader "Identity Providers:"
      for provider in $PROVIDERS; do
        echo "      - $provider"
      done
    fi
    echo ""
  done
fi

###############################################################################
# API Gateway (HTTP APIs)
###############################################################################

print_header "API GATEWAY - HTTP APIs"
HTTP_APIS=$(aws apigatewayv2 get-apis $PROFILE_FLAG --region $AWS_REGION --query 'Items[*].[ApiId,Name,ApiEndpoint]' --output text 2>/dev/null)
if [ -z "$HTTP_APIS" ]; then
  echo "  No HTTP APIs found"
else
  echo "$HTTP_APIS" | while read -r id name endpoint; do
    echo "  • $name"
    echo "    ID:       $id"
    echo "    Endpoint: $endpoint"
    echo ""
  done
fi

###############################################################################
# API Gateway (REST APIs)
###############################################################################

print_header "API GATEWAY - REST APIs"
REST_APIS=$(aws apigateway get-rest-apis $PROFILE_FLAG --region $AWS_REGION --query 'items[*].[id,name]' --output text 2>/dev/null)
if [ -z "$REST_APIS" ]; then
  echo "  No REST APIs found"
else
  echo "$REST_APIS" | while read -r id name; do
    echo "  • $name (ID: $id)"
  done
fi

###############################################################################
# DynamoDB Tables
###############################################################################

print_header "DYNAMODB TABLES"
TABLES=$(aws dynamodb list-tables $PROFILE_FLAG --region $AWS_REGION --query 'TableNames' --output text 2>/dev/null)
if [ -z "$TABLES" ]; then
  echo "  No tables found"
else
  for table in $TABLES; do
    STATUS=$(aws dynamodb describe-table $PROFILE_FLAG --table-name "$table" --region $AWS_REGION --query 'Table.TableStatus' --output text 2>/dev/null)
    ITEM_COUNT=$(aws dynamodb describe-table $PROFILE_FLAG --table-name "$table" --region $AWS_REGION --query 'Table.ItemCount' --output text 2>/dev/null)
    echo "  • $table"
    echo "    Status: $STATUS | Items: $ITEM_COUNT"
  done
fi

###############################################################################
# Lambda Functions
###############################################################################

print_header "LAMBDA FUNCTIONS"
FUNCTIONS=$(aws lambda list-functions $PROFILE_FLAG --region $AWS_REGION --query 'Functions[*].[FunctionName,Runtime,LastModified]' --output text 2>/dev/null)
if [ -z "$FUNCTIONS" ]; then
  echo "  No functions found"
else
  echo "$FUNCTIONS" | while read -r name runtime modified; do
    echo "  • $name"
    echo "    Runtime: $runtime | Modified: $modified"
  done
fi

###############################################################################
# IAM Roles
###############################################################################

print_header "IAM ROLES"
ROLES=$(aws iam list-roles $PROFILE_FLAG --query 'Roles[*].[RoleName,CreateDate]' --output text 2>/dev/null)
if [ -z "$ROLES" ]; then
  echo "  No roles found"
else
  echo "$ROLES" | while read -r name created; do
    echo "  • $name"
  done
fi

###############################################################################
# CloudWatch Log Groups
###############################################################################

print_header "CLOUDWATCH LOG GROUPS"
LOG_GROUPS=$(aws logs describe-log-groups $PROFILE_FLAG --region $AWS_REGION --query 'logGroups[*].[logGroupName,storedBytes]' --output text 2>/dev/null)
if [ -z "$LOG_GROUPS" ]; then
  echo "  No log groups found"
else
  echo "$LOG_GROUPS" | while read -r name bytes; do
    size_mb=$(echo "scale=2; ${bytes:-0} / 1048576" | bc 2>/dev/null || echo "0")
    echo "  • $name (${size_mb} MB)"
  done
fi

###############################################################################
# Summary
###############################################################################

print_header "SUMMARY"
printf "  %-20s %d\n" "S3 Buckets:" "$(echo "$BUCKETS" | grep -c . 2>/dev/null)"
printf "  %-20s %d\n" "Cognito Pools:" "$(echo "$POOLS" | grep -c . 2>/dev/null)"
printf "  %-20s %d\n" "HTTP APIs:" "$(echo "$HTTP_APIS" | grep -c . 2>/dev/null)"
printf "  %-20s %d\n" "REST APIs:" "$(echo "$REST_APIS" | grep -c . 2>/dev/null)"
printf "  %-20s %d\n" "DynamoDB Tables:" "$(echo "$TABLES" | wc -w 2>/dev/null)"
printf "  %-20s %d\n" "Lambda Functions:" "$(echo "$FUNCTIONS" | grep -c . 2>/dev/null)"
echo ""