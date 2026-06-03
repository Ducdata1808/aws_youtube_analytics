#!/bin/bash
echo "=========== Creating CloudWatch Log Groups ==========="

# 1. Create Log Group for Lambda Cleanse & Enrich
echo "Creating log group: /aws/lambda/cleanse-enrich..."
awslocal logs create-log-group --log-group-name /aws/lambda/cleanse-enrich

# Set retention policy (e.g., keep logs for 7 days to optimize storage)
awslocal logs put-retention-policy --log-group-name /aws/lambda/cleanse-enrich --retention-in-days 7

# 2. Create Log Group for Lambda Transform & Analytics
echo "Creating log group: /aws/lambda/transform-analytics..."
awslocal logs create-log-group --log-group-name /aws/lambda/transform-analytics
awslocal logs put-retention-policy --log-group-name /aws/lambda/transform-analytics --retention-in-days 7

# 3. Create Log Group for Custom Pipeline Metrics
echo "Creating log group: /youtube-analytics/pipeline-metrics..."
awslocal logs create-log-group --log-group-name /youtube-analytics/pipeline-metrics
awslocal logs put-retention-policy --log-group-name /youtube-analytics/pipeline-metrics --retention-in-days 7

# 4. Verify list of Log Groups created
echo "List of created CloudWatch Log Groups:"
awslocal logs describe-log-groups --query 'logGroups[*].logGroupName' --output table

echo "=========== CloudWatch Setup Completed Successfully ==========="
