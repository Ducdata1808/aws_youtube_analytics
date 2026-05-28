from datetime import datetime, timedelta
import json
import boto3
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator

# Danh sách 10 quốc gia
COUNTRIES = ["US", "GB", "DE", "FR", "CA", "RU", "MX", "KR", "JP", "IN"]

default_args = {
    "owner": "airflow",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=2),
}

# Hàm Python dùng boto3 để gọi Lambda trên LocalStack
def invoke_lambda_func(function_name, payload_dict):
    # Kết nối trực tiếp tới localstack container qua Docker network
    client = boto3.client(
        "lambda",
        endpoint_url="http://localstack:4566",
        region_name="us-east-1",
        aws_access_key_id="test",
        aws_secret_access_key="test",
    )
    
    print(f"Calling Lambda function: {function_name} with payload: {payload_dict}")
    
    response = client.invoke(
        FunctionName=function_name,
        InvocationType="RequestResponse",
        Payload=json.dumps(payload_dict),
    )
    
    # Đọc kết quả phản hồi từ Lambda
    response_payload = json.loads(response["Payload"].read().decode("utf-8"))
    print(f"Lambda Response: {json.dumps(response_payload, indent=2)}")
    
    # Nếu Lambda trả về lỗi ứng dụng (Unhandled / Handled)
    if "FunctionError" in response:
        error_msg = response_payload.get("errorMessage", "Unknown error in Lambda execution")
        raise Exception(f"Lambda execution failed: {error_msg}")
        
    return response_payload

with DAG(
    "youtube_trending_pipeline",
    default_args=default_args,
    description="Pipeline phân tích Trending YouTube Videos (LocalStack + ClickHouse)",
    schedule_interval=None,
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["youtube", "analytics"],
) as dag:

    # Task 1: Upload dữ liệu thô
    upload_raw_data = BashOperator(
        task_id="upload_raw_to_landing",
        bash_command="python /opt/airflow/scripts/upload_to_landing.py",
    )

    # Task 3: Kích hoạt Lambda 2 (transform-analytics)
    invoke_transform = PythonOperator(
        task_id="invoke_transform_analytics",
        python_callable=invoke_lambda_func,
        op_kwargs={
            "function_name": "transform-analytics",
            "payload_dict": {}
        }
    )

    # Task 2 (Parallel): Đọc thô -> Chuẩn hoá Parquet
    for country in COUNTRIES:
        invoke_cleanse = PythonOperator(
            task_id=f"invoke_cleanse_enrich_{country}",
            python_callable=invoke_lambda_func,
            op_kwargs={
                "function_name": "cleanse-enrich",
                "payload_dict": {"country": country}
            }
        )
        
        upload_raw_data >> invoke_cleanse >> invoke_transform
