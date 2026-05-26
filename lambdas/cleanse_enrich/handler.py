import os
import re
import json
import io
import boto3
import pandas as pd
from datetime import datetime

# LocalStack endpoint cấu hình (nếu chạy local ngoài Lambda)
LOCALSTACK_HOSTNAME = os.environ.get("LOCALSTACK_HOSTNAME", "localhost")
AWS_REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")

# Kiểm tra xem có đang chạy cục bộ (ngoài LocalStack container) hay không
# Nếu chạy trong LocalStack, biến LOCALSTACK_HOSTNAME hoặc AWS_SAM_LOCAL sẽ tồn tại
IS_LOCAL = not os.environ.get("AWS_LAMBDA_FUNCTION_NAME")

if IS_LOCAL:
    print("Chạy ở local: Cấu hình boto3 kết nối tới LocalStack endpoint (http://127.0.0.1:4566)")
    s3_client = boto3.client(
        "s3",
        endpoint_url="http://127.0.0.1:4566",
        aws_access_key_id="test",
        aws_secret_access_key="test",
        region_name=AWS_REGION
    )
else:
    s3_client = boto3.client("s3")

def get_country_from_filename(filename):
    match = re.match(r"([A-Z]{2})videos\.csv", filename)
    return match.group(1) if match else "US"

def lambda_handler(event, context):
    print(f"Nhận event: {json.dumps(event)}")
    
    country = event.get("country", "US")
    csv_key = f"{country}videos.csv"
    json_key = f"{country}_category_id.json"
    
    landing_bucket = os.environ.get("LANDING_BUCKET", "yt-landing-bucket")
    cleansed_bucket = os.environ.get("CLEANSED_BUCKET", "yt-cleansed-bucket")
    
    print(f"Đang xử lý dữ liệu quốc gia: {country} từ {landing_bucket} -> {cleansed_bucket}")
    
    try:
        json_obj = s3_client.get_object(Bucket=landing_bucket, Key=json_key)
        category_data = json.loads(json_obj["Body"].read().decode("utf-8"))
        
        category_map = {}
        for item in category_data.get("items", []):
            cat_id = int(item["id"])
            cat_title = item["snippet"]["title"]
            category_map[cat_id] = cat_title
            
        csv_obj = s3_client.get_object(Bucket=landing_bucket, Key=csv_key)
        csv_data = csv_obj["Body"].read()
        
        # Thử đọc bằng UTF-8 trước, nếu lỗi thì chuyển sang latin-1
        try:
            df = pd.read_csv(io.BytesIO(csv_data), on_bad_lines="skip", encoding="utf-8")
        except UnicodeDecodeError:
            print(f"Lưu ý: Không thể decode UTF-8 cho {csv_key}. Chuyển sang sử dụng encoding='latin-1'")
            df = pd.read_csv(io.BytesIO(csv_data), on_bad_lines="skip", encoding="latin-1")
        
        print(f"Đọc thành công {len(df)} dòng dữ liệu từ {csv_key}")
        
        # Clean & Enrich dữ liệu
        def parse_trending_date(d_str):
            try:
                if pd.isna(d_str) or not isinstance(d_str, str):
                    return None
                parts = d_str.split(".")
                if len(parts) == 3:
                    year = f"20{parts[0]}"
                    day = parts[1]
                    month = parts[2]
                    return f"{year}-{month}-{day}"
                return None
            except:
                return None

        df["trending_date"] = df["trending_date"].apply(parse_trending_date)
        df["trending_date"] = pd.to_datetime(df["trending_date"], errors="coerce")
        
        df["publish_time"] = pd.to_datetime(df["publish_time"], errors="coerce")
        df["publish_date"] = df["publish_time"].dt.date
        df["publish_hour"] = df["publish_time"].dt.hour
        
        numeric_cols = ["views", "likes", "dislikes", "comment_count"]
        for col in numeric_cols:
            df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0).astype("int64")
            
        bool_cols = ["comments_disabled", "ratings_disabled", "video_error_or_removed"]
        for col in bool_cols:
            df[col] = df[col].astype(bool)
            
        df["description"] = df["description"].fillna("")
        df["tags"] = df["tags"].fillna("")
        
        df["category_id"] = pd.to_numeric(df["category_id"], errors="coerce").fillna(0).astype(int)
        df["category_name"] = df["category_id"].map(category_map).fillna("Unknown")
        
        df["country"] = country
        
        df["engagement_rate"] = (df["likes"] + df["dislikes"] + df["comment_count"]) / df["views"]
        df["engagement_rate"] = df["engagement_rate"].fillna(0)
        
        total_votes = df["likes"] + df["dislikes"]
        df["like_ratio"] = df["likes"] / total_votes
        df["like_ratio"] = df["like_ratio"].fillna(0)
        
        df["tags_count"] = df["tags"].apply(lambda t: 0 if t == "[none]" or t == "" else len(t.split("|")))
        df["title_length"] = df["title"].fillna("").apply(len)
        
        df_cleaned = df.drop(columns=["publish_time"], errors="ignore")
        
        parquet_buffer = io.BytesIO()
        df_cleaned.to_parquet(parquet_buffer, index=False, engine="pyarrow", compression="snappy")
        
        target_key = f"country={country}/data.parquet"
        
        s3_client.put_object(
            Bucket=cleansed_bucket,
            Key=target_key,
            Body=parquet_buffer.getvalue()
        )
        
        print(f"Lưu thành công Parquet lên S3: s3://{cleansed_bucket}/{target_key} ({len(df_cleaned)} dòng)")
        
        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": f"Cleanse & Enrich thành công cho {country}",
                "records_processed": len(df_cleaned),
                "cleansed_s3_uri": f"s3://{cleansed_bucket}/{target_key}"
            })
        }
        
    except Exception as e:
        print(f"LỖI trong Lambda cleanse_enrich cho quốc gia {country}: {str(e)}")
        import traceback
        traceback.print_exc()
        raise e

# Thêm block này để chạy test trực tiếp khi gọi python handler.py
if __name__ == "__main__":
    os.environ["LANDING_BUCKET"] = os.environ.get("LANDING_BUCKET", "yt-landing-bucket")
    os.environ["CLEANSED_BUCKET"] = os.environ.get("CLEANSED_BUCKET", "yt-cleansed-bucket")
    
    print("--- CHẠY THỬ LAMBDA CLEANSE ENRICH LOCALLY (ALL COUNTRIES) ---")
    
    # Liệt kê tất cả các file trong Landing Bucket để tìm các quốc gia có dữ liệu
    try:
        response = s3_client.list_objects_v2(Bucket=os.environ["LANDING_BUCKET"])
        contents = response.get("Contents", [])
        
        # Tìm các file CSV dạng [XX]videos.csv
        countries = []
        for obj in contents:
            key = obj["Key"]
            match = re.match(r"^([A-Z]{2})videos\.csv$", key)
            if match:
                countries.append(match.group(1))
                
        if not countries:
            print("Không tìm thấy tệp tin CSV của quốc gia nào trong landing bucket.")
            print("Vui lòng chạy scripts/upload_to_landing.py trước!")
        else:
            print(f"Tìm thấy dữ liệu của các quốc gia trong Landing Bucket: {countries}")
            for country in countries:
                print(f"\n>> Đang xử lý quốc gia: {country} ...")
                try:
                    result = lambda_handler({"country": country}, None)
                    print(f"Xử lý thành công {country}: {result}")
                except Exception as err:
                    print(f"Lỗi khi xử lý quốc gia {country}: {err}")
                    
    except Exception as e:
        print(f"Không thể kết nối hoặc lấy danh sách file từ S3 landing bucket: {e}")
