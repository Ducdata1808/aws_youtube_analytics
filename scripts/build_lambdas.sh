#!/bin/bash

# Lambda packaging script optimized for size (Unzipped size < 250MB)
# Can be run independently in WSL Ubuntu without dependency on Docker/LocalStack.

echo "=========================================================="
echo "          BUILDING & OPTIMIZING LAMBDA ZIP PACKAGES       "
echo "=========================================================="

# Ensure zip files are installed
if ! command -v zip &> /dev/null; then
    echo "ERROR: 'zip' command is not installed in WSL."
    echo "Please run: sudo apt-get update && sudo apt-get install -y zip"
    exit 1
fi

# Get the absolute path of the project
PROJECT_ROOT="/home/duc1808/aws_youtube_analytics"
cd "${PROJECT_ROOT}"

LAMBDAS=("cleanse_enrich" "transform_analytics")

for LAMBDA in "${LAMBDAS[@]}"; do
    # Back to the root directory before each build to avoid pip directory loss
    cd "${PROJECT_ROOT}"

    echo "----------------------------------------------------------"
    echo "Processing: ${LAMBDA}"
    echo "----------------------------------------------------------"
    
    LAMBDA_DIR="${PROJECT_ROOT}/lambdas/${LAMBDA}"
    BUILD_DIR="/tmp/build_${LAMBDA}"
    ZIP_PATH="${LAMBDA_DIR}/lambda_${LAMBDA}.zip"
    
    # 1. Create and clean up the absolute build directory
    rm -rf "${BUILD_DIR}"
    rm -f "${ZIP_PATH}"
    mkdir -p "${BUILD_DIR}"
    
    # 2. Install dependencies compatible with AWS Lambda Linux x86_64 environment
    if [ -f "${LAMBDA_DIR}/requirements.txt" ]; then
        echo "Installing AWS Lambda compatible dependencies (manylinux)..."
        # Use --platform and --only-binary flags to download the correct distribution for AWS Lambda (Python 3.10)
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
    
    # 3. Copy source code handler to build directory
    cp "${LAMBDA_DIR}/handler.py" "${BUILD_DIR}/"
    
    # 4. Optimize package size (removing comments, tests, pycache)
    echo "Optimizing package size (removing comments, tests, pycache)..."
    cd "${BUILD_DIR}"
    find . -type d -name "tests" -exec rm -rf {} +
    find . -type d -name "__pycache__" -exec rm -rf {} +
    find . -name "*.pyc" -delete
    find . -name "*.pyo" -delete
    find . -name "*.dist-info" -exec rm -rf {} +
    find . -name "*.egg-info" -exec rm -rf {} +
    
    # Remove large binary executable files if any
    find . -name "*.so" -exec strip --strip-unneeded {} + 2>/dev/null || true
    
    # 5. Zip package
    echo "Zipping package..."
    zip -r -q "${ZIP_PATH}" .
    
    # Get zip file size
    if [ -f "${ZIP_PATH}" ]; then
        ZIP_SIZE=$(du -sh "${ZIP_PATH}" | cut -f1)
        echo "Zip package created successfully: ${ZIP_SIZE}"
        echo "Saved to: lambdas/${LAMBDA}/lambda_${LAMBDA}.zip"
    else
        echo "ERROR: Failed to create zip package."
    fi
    
    # Clean up the temporary build directory
    rm -rf "${BUILD_DIR}"
done

# Back to the root directory
cd "${PROJECT_ROOT}"

echo "=========================================================="
echo "                 ALL LAMBDAS BUILT!                       "
echo "=========================================================="
