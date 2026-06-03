#!/bin/bash

echo "=========================================================="
echo "    UPLOADING LAMBDA ZIP PACKAGES TO S3 & DEPLOYING       "
echo "=========================================================="

# Wait for bucket to be created from script 01-create-buckets.sh
# Although scripts run alphabetically, checking and waiting ensures absolute safety
DEPLOY_BUCKET="yt-landing-bucket"
DEPLOY_PREFIX="deploy"

echo "Waiting for S3 bucket ${DEPLOY_BUCKET} to be ready..."
until awslocal s3api head-bucket --bucket "${DEPLOY_BUCKET}" 2>/dev/null; do
    sleep 1
done

# Define ARN IAM Role for Lambda
ROLE_ARN="arn:aws:iam::000000000000:role/lambda-s3-role"

# Mount path from host
SRC_DIR="/opt/lambdas"

# 1. Lambda Cleanse & Enrich
echo "----------------------------------------------------------"
echo "Deploying Lambda: cleanse-enrich"
echo "----------------------------------------------------------"
ZIP_CE_PATH="${SRC_DIR}/cleanse_enrich/lambda_cleanse_enrich.zip"

if [ -f "${ZIP_CE_PATH}" ]; then
    echo "Uploading lambda_cleanse_enrich.zip to S3..."
    awslocal s3 cp "${ZIP_CE_PATH}" "s3://${DEPLOY_BUCKET}/${DEPLOY_PREFIX}/lambda_cleanse_enrich.zip"
    
    echo "Registering Lambda Function cleanse-enrich..."
    awslocal lambda delete-function --function-name cleanse-enrich 2>/dev/null || true
    
    awslocal lambda create-function \
        --function-name cleanse-enrich \
        --runtime python3.10 \
        --role "${ROLE_ARN}" \
        --handler handler.lambda_handler \
        --code S3Bucket="${DEPLOY_BUCKET}",S3Key="${DEPLOY_PREFIX}/lambda_cleanse_enrich.zip" \
        --timeout 120 \
        --memory-size 512 \
        --environment "Variables={LANDING_BUCKET=yt-landing-bucket,CLEANSED_BUCKET=yt-cleansed-bucket,ANALYTICS_BUCKET=yt-analytics-bucket}"
        
    echo "Successfully deployed Lambda: cleanse-enrich"
else
    echo "ERROR: File ${ZIP_CE_PATH} not found. Please pack it first."
fi

# 2. Lambda Transform & Analytics
echo "----------------------------------------------------------"
echo "Deploying Lambda: transform-analytics"
echo "----------------------------------------------------------"
ZIP_TA_PATH="${SRC_DIR}/transform_analytics/lambda_transform_analytics.zip"

if [ -f "${ZIP_TA_PATH}" ]; then
    echo "Uploading lambda_transform_analytics.zip to S3..."
    awslocal s3 cp "${ZIP_TA_PATH}" "s3://${DEPLOY_BUCKET}/${DEPLOY_PREFIX}/lambda_transform_analytics.zip"
    
    echo "Registering Lambda Function transform-analytics..."
    awslocal lambda delete-function --function-name transform-analytics 2>/dev/null || true
    
    awslocal lambda create-function \
        --function-name transform-analytics \
        --runtime python3.10 \
        --role "${ROLE_ARN}" \
        --handler handler.lambda_handler \
        --code S3Bucket="${DEPLOY_BUCKET}",S3Key="${DEPLOY_PREFIX}/lambda_transform_analytics.zip" \
        --timeout 120 \
        --memory-size 512 \
        --environment "Variables={LANDING_BUCKET=yt-landing-bucket,CLEANSED_BUCKET=yt-cleansed-bucket,ANALYTICS_BUCKET=yt-analytics-bucket}"
        
    echo "Successfully deployed Lambda: transform-analytics"
else
    echo "ERROR: File ${ZIP_TA_PATH} not found. Please pack it first."
fi

echo "=========================================================="
echo "       ALL LAMBDAS SUCCESSFULLY DEPLOYED VIA S3           "
echo "=========================================================="
