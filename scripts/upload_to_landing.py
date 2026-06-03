import os
import glob
import boto3
from botocore.config import Config
from dotenv import load_dotenv

# Load environmental variable from .env (If any)
load_dotenv()

# Check if running inside Docker/Container then change endpoint to localstack
IS_INSIDE_DOCKER = os.path.exists("/.dockerenv")

if IS_INSIDE_DOCKER:
    LOCALSTACK_ENDPOINT = "http://localstack:4566"
else:
    LOCALSTACK_ENDPOINT = os.getenv("LOCALSTACK_ENDPOINT", "http://localhost:4566")

LANDING_BUCKET = os.getenv("LANDING_BUCKET", "yt-landing-bucket")
RAW_DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data", "raw")

# Using LocalStack virtual credentials
s3_client = boto3.client(
    "s3",
    endpoint_url=LOCALSTACK_ENDPOINT,
    aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID", "test"),
    aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY", "test"),
    region_name=os.getenv("AWS_DEFAULT_REGION", "us-east-1"),
    config=Config(signature_version="s3v4")
)

def upload_files():
    print(f"Starting upload process from: {RAW_DATA_DIR}")
    print(f"Using Endpoint S3: {LOCALSTACK_ENDPOINT}")
    print(f"Target Bucket: {LANDING_BUCKET}")
    
    if not os.path.exists(RAW_DATA_DIR):
        error_msg = f"ERROR: Directory {RAW_DATA_DIR} does not exist. Please download the dataset from Kaggle first."
        print(error_msg)
        raise Exception(error_msg)

    # Find csv and json files in data/raw
    csv_files = glob.glob(os.path.join(RAW_DATA_DIR, "*videos.csv"))
    json_files = glob.glob(os.path.join(RAW_DATA_DIR, "*_category_id.json"))
    files_to_upload = csv_files + json_files

    if not files_to_upload:
        error_msg = "No .csv or .json files found in data/raw."
        print(error_msg)
        raise Exception(error_msg)

    for file_path in files_to_upload:
        file_name = os.path.basename(file_path)
        print(f"Uploading {file_name}...")
        try:
            s3_client.upload_file(file_path, LANDING_BUCKET, file_name)
            print(f"Successfully uploaded {file_name}")
        except Exception as e:
            print(f"Error uploading {file_name}: {e}")
            # Raise exception to Airflow to recognize error and mark task as FAILED
            raise e

    print("Completed uploading to landing bucket!")

if __name__ == "__main__":
    upload_files()
