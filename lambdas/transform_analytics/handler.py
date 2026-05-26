import os
import json
import io
import boto3
import pandas as pd

# Kiểm tra xem có đang chạy cục bộ (ngoài LocalStack container) hay không
IS_LOCAL = not os.environ.get("AWS_LAMBDA_FUNCTION_NAME")
AWS_REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")

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

def lambda_handler(event, context):
    print(f"Nhận event: {json.dumps(event)}")
    
    cleansed_bucket = os.environ.get("CLEANSED_BUCKET", "yt-cleansed-bucket")
    analytics_bucket = os.environ.get("ANALYTICS_BUCKET", "yt-analytics-bucket")
    
    try:
        response = s3_client.list_objects_v2(Bucket=cleansed_bucket)
        objects = response.get("Contents", [])
        
        parquet_keys = [obj["Key"] for obj in objects if obj["Key"].endswith(".parquet")]
        
        if not parquet_keys:
            print("Không tìm thấy tệp Parquet nào trong cleansed bucket để transform.")
            return {
                "statusCode": 200,
                "body": json.dumps({"message": "Không có tệp Parquet nào được tìm thấy."})
            }
            
        print(f"Tìm thấy các key Parquet trong cleansed bucket: {parquet_keys}")
        
        df_list = []
        for key in parquet_keys:
            print(f"Đang đọc tệp cleansed: {key}")
            obj = s3_client.get_object(Bucket=cleansed_bucket, Key=key)
            country_df = pd.read_parquet(io.BytesIO(obj["Body"].read()))
            df_list.append(country_df)
            
        df = pd.concat(df_list, ignore_index=True)
        print(f"Tổng số bản ghi tích hợp từ các quốc gia: {len(df)}")
        
        # --- TRANSFORM & AGGREGATE ---
        
        # 1. Fact Table: fact_trending_videos
        fact_df = df.copy()
        if "trending_date" in fact_df.columns:
            fact_df["trending_date"] = pd.to_datetime(fact_df["trending_date"]).dt.strftime("%Y-%m-%d")
        if "publish_date" in fact_df.columns:
            fact_df["publish_date"] = pd.to_datetime(fact_df["publish_date"]).dt.strftime("%Y-%m-%d")
            
        for country, group in fact_df.groupby("country"):
            fact_buffer = io.BytesIO()
            group.to_parquet(fact_buffer, index=False, engine="pyarrow", compression="snappy")
            s3_client.put_object(
                Bucket=analytics_bucket,
                Key=f"fact_trending_videos/country={country}/data.parquet",
                Body=fact_buffer.getvalue()
            )
            
        # 2. Agg Table 1: agg_category_stats (Thống kê theo category & country)
        agg_cat = df.groupby(["country", "category_name"]).agg(
            total_videos=("video_id", "count"),
            avg_views=("views", "mean"),
            avg_likes=("likes", "mean"),
            avg_engagement_rate=("engagement_rate", "mean"),
            total_views=("views", "sum"),
            max_views=("views", "max")
        ).reset_index()
        
        cat_buffer = io.BytesIO()
        agg_cat.to_parquet(cat_buffer, index=False, engine="pyarrow", compression="snappy")
        s3_client.put_object(
            Bucket=analytics_bucket,
            Key="agg_category_stats/data.parquet",
            Body=cat_buffer.getvalue()
        )
        
        # 3. Agg Table 2: agg_channel_performance (Thống kê theo kênh/channel)
        agg_channel = df.groupby(["country", "channel_title"]).agg(
            trending_count=("video_id", "count"),
            unique_videos=("video_id", "nunique"),
            total_views=("views", "sum"),
            avg_engagement_rate=("engagement_rate", "mean")
        ).reset_index()
        
        def get_top_category(group):
            return group["category_name"].value_counts().idxmax()
            
        top_cats = df.groupby(["country", "channel_title"]).apply(get_top_category, include_groups=False).reset_index()
        top_cats.columns = ["country", "channel_title", "top_category"]
        
        agg_channel = pd.merge(agg_channel, top_cats, on=["country", "channel_title"], how="left")
        
        channel_buffer = io.BytesIO()
        agg_channel.to_parquet(channel_buffer, index=False, engine="pyarrow", compression="snappy")
        s3_client.put_object(
            Bucket=analytics_bucket,
            Key="agg_channel_performance/data.parquet",
            Body=channel_buffer.getvalue()
        )
        
        # 4. Agg Table 3: agg_time_analysis (Phân tích xu hướng theo thời gian)
        time_df = df.copy()
        time_df["trending_date"] = pd.to_datetime(time_df["trending_date"])
        time_df["day_of_week"] = time_df["trending_date"].dt.day_name()
        
        agg_time = time_df.groupby(["country", "trending_date", "day_of_week"]).agg(
            total_videos=("video_id", "count"),
            avg_views=("views", "mean"),
            avg_publish_hour=("publish_hour", "mean")
        ).reset_index()
        
        def get_top_cat_by_day(group):
            return group["category_name"].value_counts().idxmax()
            
        top_cats_day = time_df.groupby(["country", "trending_date"]).apply(get_top_cat_by_day, include_groups=False).reset_index()
        top_cats_day.columns = ["country", "trending_date", "top_category"]
        
        agg_time = pd.merge(agg_time, top_cats_day, on=["country", "trending_date"], how="left")
        agg_time["trending_date"] = agg_time["trending_date"].dt.strftime("%Y-%m-%d")
        
        time_buffer = io.BytesIO()
        agg_time.to_parquet(time_buffer, index=False, engine="pyarrow", compression="snappy")
        s3_client.put_object(
            Bucket=analytics_bucket,
            Key="agg_time_analysis/data.parquet",
            Body=time_buffer.getvalue()
        )
        
        print("Transform thành công và đẩy các bảng dữ liệu lên Analytics Bucket!")
        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "Transform & Aggregation thành công!",
                "fact_records": len(fact_df),
                "analytics_s3_uri": f"s3://{analytics_bucket}/"
            })
        }
        
    except Exception as e:
        print(f"LỖI trong Lambda transform_analytics: {str(e)}")
        import traceback
        traceback.print_exc()
        raise e

# Thêm block này để chạy test trực tiếp khi gọi python handler.py
if __name__ == "__main__":
    os.environ["CLEANSED_BUCKET"] = os.environ.get("CLEANSED_BUCKET", "yt-cleansed-bucket")
    os.environ["ANALYTICS_BUCKET"] = os.environ.get("ANALYTICS_BUCKET", "yt-analytics-bucket")
    
    print("--- CHẠY THỬ LAMBDA TRANSFORM ANALYTICS LOCALLY ---")
    result = lambda_handler({}, None)
    print("Kết quả chạy thử:")
    print(result)
