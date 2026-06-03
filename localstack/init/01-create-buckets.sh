#!/bin/bash
echo "=========== Creating S3 Buckets ==========="

# Create buckets with awslocal (equivalent to aws --endpoint-url=http://localhost:4566)
awslocal s3 mb s3://yt-landing-bucket
awslocal s3 mb s3://yt-cleansed-bucket
awslocal s3 mb s3://yt-analytics-bucket

# List buckets to verify
echo "List of created S3 buckets:"
awslocal s3 ls

echo "=========== S3 Buckets Created Successfully ==========="
