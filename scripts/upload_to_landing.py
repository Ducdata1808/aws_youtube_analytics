import os
import glob
import boto3
from botocore.config import Config
from dotenv import load_dotenv

# Load biến môi trường từ .env
load_dotenv()

# Cấu hình kết nối tới LocalStack S3
LOCALSTACK_ENDPOINT = os.getenv("LOCALSTACK_ENDPOINT", "http://localhost:4566")
LANDING_BUCKET = os.getenv("LANDING_BUCKET", "yt-landing-bucket")
RAW_DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data", "raw")

# Sử dụng credentials ảo của LocalStack
s3_client = boto3.client(
    "s3",
    endpoint_url=LOCALSTACK_ENDPOINT,
    aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID", "test"),
    aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY", "test"),
    region_name=os.getenv("AWS_DEFAULT_REGION", "us-east-1"),
    config=Config(signature_version="s3v4")
)

def upload_files():
    print(f"Bắt đầu upload dữ liệu từ: {RAW_DATA_DIR}")
    print(f"Target Bucket: {LANDING_BUCKET}")
    
    if not os.path.exists(RAW_DATA_DIR):
        print(f"LỖI: Thư mục {RAW_DATA_DIR} không tồn tại. Hãy tải bộ dữ liệu từ Kaggle về trước.")
        return

    # Tìm các file csv và json trong data/raw
    csv_files = glob.glob(os.path.join(RAW_DATA_DIR, "*videos.csv"))
    json_files = glob.glob(os.path.join(RAW_DATA_DIR, "*_category_id.json"))
    files_to_upload = csv_files + json_files

    if not files_to_upload:
        print("Không tìm thấy file .csv hoặc .json nào trong data/raw.")
        print("Vui lòng tải bộ dữ liệu 'Trending YouTube Video Statistics' từ Kaggle về và giải nén vào data/raw.")
        return

    for file_path in files_to_upload:
        file_name = os.path.basename(file_path)
        print(f"Đang upload {file_name}...")
        try:
            s3_client.upload_file(file_path, LANDING_BUCKET, file_name)
            print(f"Đã upload thành công {file_name}")
        except Exception as e:
            print(f"Lỗi khi upload {file_name}: {e}")

    print("Hoàn thành quá trình tải dữ liệu lên landing bucket!")

if __name__ == "__main__":
    upload_files()
