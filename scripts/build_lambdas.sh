#!/bin/bash

# Script đóng gói Lambda tối ưu hóa dung lượng (Unzipped size < 250MB)
# Có thể chạy độc lập ở WSL Ubuntu không phụ thuộc vào Docker/LocalStack.

echo "=========================================================="
echo "          BUILDING & OPTIMIZING LAMBDA ZIP PACKAGES       "
echo "=========================================================="

# Đảm bảo lệnh zip được cài đặt
if ! command -v zip &> /dev/null; then
    echo "ERROR: 'zip' command is not installed in WSL."
    echo "Please run: sudo apt-get update && sudo apt-get install -y zip"
    exit 1
fi

# Lấy đường dẫn tuyệt đối của dự án
PROJECT_ROOT="/home/duc1808/aws_youtube_analytics"
cd "${PROJECT_ROOT}"

LAMBDAS=("cleanse_enrich" "transform_analytics")

for LAMBDA in "${LAMBDAS[@]}"; do
    # Về lại thư mục gốc trước mỗi lần build để tránh lỗi mất thư mục của pip
    cd "${PROJECT_ROOT}"

    echo "----------------------------------------------------------"
    echo "Processing: ${LAMBDA}"
    echo "----------------------------------------------------------"
    
    LAMBDA_DIR="${PROJECT_ROOT}/lambdas/${LAMBDA}"
    BUILD_DIR="/tmp/build_${LAMBDA}"
    ZIP_PATH="${LAMBDA_DIR}/lambda_${LAMBDA}.zip"
    
    # 1. Tạo mới và dọn dẹp thư mục build tuyệt đối
    rm -rf "${BUILD_DIR}"
    rm -f "${ZIP_PATH}"
    mkdir -p "${BUILD_DIR}"
    
    # 2. Cài đặt các thư viện tương thích với môi trường AWS Lambda Linux x86_64
    if [ -f "${LAMBDA_DIR}/requirements.txt" ]; then
        echo "Installing AWS Lambda compatible dependencies (manylinux)..."
        # Sử dụng các cờ --platform và --only-binary để tải đúng bản phân phối cho AWS Lambda (Python 3.10)
        pip install \
            --target "${BUILD_DIR}" \
            -r "${LAMBDA_DIR}/requirements.txt" \
            --platform manylinux2014_x86_64 \
            --only-binary=:all: \
            --implementation cp \
            --python-version 3.10 \
            --no-cache-dir \
            --quiet
    else
        echo "No requirements.txt found. Packing code only."
    fi
    
    # 3. Copy source code handler vào thư mục build
    cp "${LAMBDA_DIR}/handler.py" "${BUILD_DIR}/"
    
    # 4. Tối ưu hóa dung lượng: Xoá bỏ toàn bộ file tests, cache, doc thừa
    echo "Optimizing package size (removing comments, tests, pycache)..."
    cd "${BUILD_DIR}"
    find . -type d -name "tests" -exec rm -rf {} +
    find . -type d -name "__pycache__" -exec rm -rf {} +
    find . -name "*.pyc" -delete
    find . -name "*.pyo" -delete
    find . -name "*.dist-info" -exec rm -rf {} +
    find . -name "*.egg-info" -exec rm -rf {} +
    
    # Xoá các file thực thi nhị phân khổng lồ không dùng đến nếu có
    find . -name "*.so" -exec strip --strip-unneeded {} + 2>/dev/null || true
    
    # 5. Đóng gói thành file .zip
    echo "Zipping package..."
    zip -r -q "${ZIP_PATH}" .
    
    # Lấy dung lượng file zip
    if [ -f "${ZIP_PATH}" ]; then
        ZIP_SIZE=$(du -sh "${ZIP_PATH}" | cut -f1)
        echo "Zip package created successfully: ${ZIP_SIZE}"
        echo "Saved to: lambdas/${LAMBDA}/lambda_${LAMBDA}.zip"
    else
        echo "ERROR: Failed to create zip package."
    fi
    
    # Dọn dẹp thư mục build tạm
    rm -rf "${BUILD_DIR}"
done

# Trả về thư mục gốc
cd "${PROJECT_ROOT}"

echo "=========================================================="
echo "                 ALL LAMBDAS BUILT!                       "
echo "=========================================================="
