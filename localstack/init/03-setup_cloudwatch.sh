#!/bin/bash
echo "=========== Creating CloudWatch Log Groups ==========="

# 1. Tạo Log Group cho Lambda Cleanse & Enrich
echo "Creating log group: /aws/lambda/cleanse-enrich..."
awslocal logs create-log-group --log-group-name /aws/lambda/cleanse-enrich

# Thiết lập retention policy (ví dụ: giữ log trong 7 ngày để tối ưu dung lượng)
awslocal logs put-retention-policy --log-group-name /aws/lambda/cleanse-enrich --retention-in-days 7

# 2. Tạo Log Group cho Lambda Transform & Analytics
echo "Creating log group: /aws/lambda/transform-analytics..."
awslocal logs create-log-group --log-group-name /aws/lambda/transform-analytics
awslocal logs put-retention-policy --log-group-name /aws/lambda/transform-analytics --retention-in-days 7

# 3. Tạo Log Group cho Custom Pipeline Metrics
echo "Creating log group: /youtube-analytics/pipeline-metrics..."
awslocal logs create-log-group --log-group-name /youtube-analytics/pipeline-metrics
awslocal logs put-retention-policy --log-group-name /youtube-analytics/pipeline-metrics --retention-in-days 7

# 4. Verify danh sách Log Groups đã tạo
echo "List of created CloudWatch Log Groups:"
awslocal logs describe-log-groups --query 'logGroups[*].logGroupName' --output table

echo "=========== CloudWatch Setup Completed Successfully ==========="
