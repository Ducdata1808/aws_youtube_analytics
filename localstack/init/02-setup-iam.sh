#!/bin/bash
echo "=========== Creating IAM Roles & Policies ==========="

# 1. Create trust policy (Permission for Lambda to assume this role)
TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}'

# 2. Create IAM Role for Lambda
echo "Creating role: lambda-s3-role..."
awslocal iam create-role \
  --role-name lambda-s3-role \
  --assume-role-policy-document "$TRUST_POLICY"

# 3. Create Policy for Lambda Cleanse (Read Landing -> Write Cleansed)
CLEANSE_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::yt-landing-bucket",
        "arn:aws:s3:::yt-landing-bucket/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::yt-cleansed-bucket",
        "arn:aws:s3:::yt-cleansed-bucket/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}'

echo "Creating policy: lambda-cleanse-policy..."
CLEANSE_POLICY_ARN=$(awslocal iam create-policy \
  --policy-name lambda-cleanse-policy \
  --policy-document "$CLEANSE_POLICY" \
  --query 'Policy.Arn' --output text)

# Attach Cleanse Policy to lambda-s3-role
awslocal iam attach-role-policy \
  --role-name lambda-s3-role \
  --policy-arn "$CLEANSE_POLICY_ARN"

# 4. Create Policy for Lambda Transform (Read Cleansed -> Write Analytics)
TRANSFORM_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::yt-cleansed-bucket",
        "arn:aws:s3:::yt-cleansed-bucket/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::yt-analytics-bucket",
        "arn:aws:s3:::yt-analytics-bucket/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}'

echo "Creating policy: lambda-transform-policy..."
TRANSFORM_POLICY_ARN=$(awslocal iam create-policy \
  --policy-name lambda-transform-policy \
  --policy-document "$TRANSFORM_POLICY" \
  --query 'Policy.Arn' --output text)

# Attach Transform Policy to lambda-s3-role
awslocal iam attach-role-policy \
  --role-name lambda-s3-role \
  --policy-arn "$TRANSFORM_POLICY_ARN"

# 5. Create Policy for Client/Airflow Upload to Landing Bucket (s3-landing-write-policy)
LANDING_WRITE_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::yt-landing-bucket",
        "arn:aws:s3:::yt-landing-bucket/*"
      ]
    }
  ]
}'

echo "Creating policy: s3-landing-write-policy..."
awslocal iam create-policy \
  --policy-name s3-landing-write-policy \
  --policy-document "$LANDING_WRITE_POLICY"

# 6. Create Policy for ClickHouse to read data from Analytics Bucket (s3-analytics-read-policy)
ANALYTICS_READ_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::yt-analytics-bucket",
        "arn:aws:s3:::yt-analytics-bucket/*"
      ]
    }
  ]
}'

echo "Creating policy: s3-analytics-read-policy..."
ANALYTICS_READ_POLICY_ARN=$(awslocal iam create-policy \
  --policy-name s3-analytics-read-policy \
  --policy-document "$ANALYTICS_READ_POLICY" \
  --query 'Policy.Arn' --output text)

# 7. Create IAM User for ClickHouse and attach read policy
echo "Creating user: clickhouse-user..."
awslocal iam create-user --user-name clickhouse-user

awslocal iam attach-user-policy \
  --user-name clickhouse-user \
  --policy-arn "$ANALYTICS_READ_POLICY_ARN"

# Generate Access Key from LocalStack
echo "Generating Access Key for clickhouse-user..."
CREDS=$(awslocal iam create-access-key --user-name clickhouse-user)

# Extract AccessKeyId and SecretAccessKey from JSON response
NEW_ACCESS_KEY=$(echo "$CREDS" | grep -o '"AccessKeyId": "[^"]*' | grep -o '[^"]*$')
NEW_SECRET_KEY=$(echo "$CREDS" | grep -o '"SecretAccessKey": "[^"]*' | grep -o '[^"]*$')

echo "Generated Key ID: $NEW_ACCESS_KEY"

# Replace directly in the s3_storage.xml file shared via volume mount
CLICKHOUSE_CONFIG="/opt/clickhouse-config/s3_storage.xml"

if [ -f "$CLICKHOUSE_CONFIG" ]; then
  echo "Updating ClickHouse config file: $CLICKHOUSE_CONFIG"
  sed -i "s|<access_key_id>.*</access_key_id>|<access_key_id>$NEW_ACCESS_KEY</access_key_id>|g" "$CLICKHOUSE_CONFIG"
  sed -i "s|<secret_access_key>.*</secret_access_key>|<secret_access_key>$NEW_SECRET_KEY</secret_access_key>|g" "$CLICKHOUSE_CONFIG"
  echo "ClickHouse config updated successfully."
else
  echo "Warning: ClickHouse config file not found at $CLICKHOUSE_CONFIG"
fi

# Request Clickhouse to reload configuration (note: ClickHouse automatically reloads config when detecting XML file changes, 
# but if needed, we can still use the client on the host to reload or let ClickHouse auto-detect after a few seconds)
echo "ClickHouse will auto-reload the configuration change."

# 8. Verify results
echo "List of IAM Roles:"
awslocal iam list-roles --query 'Roles[*].RoleName'

echo "List of IAM Users:"
awslocal iam list-users --query 'Users[*].UserName'

echo "List of Customer Managed Policies:"
awslocal iam list-policies --scope Local --query 'Policies[*].PolicyName'

echo "Attached Policies to lambda-s3-role:"
awslocal iam list-attached-role-policies --role-name lambda-s3-role --query 'AttachedPolicies[*].PolicyName'

echo "Attached Policies to clickhouse-user:"
awslocal iam list-attached-user-policies --user-name clickhouse-user --query 'AttachedPolicies[*].PolicyName'

echo "=========== IAM Setup Completed Successfully ==========="
