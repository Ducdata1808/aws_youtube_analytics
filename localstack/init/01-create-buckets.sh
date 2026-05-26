#!/bin/bash
echo "=========== Creating S3 Buckets ==========="

# Tạo các bucket với awslocal (tương đương aws --endpoint-url=http://localhost:4566)
awslocal s3 mb s3://yt-landing-bucket
awslocal s3 mb s3://yt-cleansed-bucket
awslocal s3 mb s3://yt-analytics-bucket

# Liệt kê danh sách các bucket để verify
echo "List of created S3 buckets:"
awslocal s3 ls

echo "=========== S3 Buckets Created Successfully ==========="
