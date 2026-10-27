#!/bin/bash

set -o pipefail

PROJECT_DIR="$HOME/Workspace/EmbeddLinux/Project"
OUTPUT_DIR="$PROJECT_DIR/build/u-boot"
LOG_FILE="$PROJECT_DIR/logs/build/uboot-build.log"

mkdir -p "$OUTPUT_DIR" "$PROJECT_DIR/logs/build"

make -j"$(nproc)" 2>&1 | tee "$LOG_FILE"
BUILD_STATUS=$?

echo "Build exit status: $BUILD_STATUS"

if [ "$BUILD_STATUS" -ne 0 ]; then
    echo "ERROR: U-Boot build failed. Images were not copied."
    exit "$BUILD_STATUS"
fi

echo "Copying U-Boot images..."

for image in MLO u-boot.img u-boot u-boot.bin u-boot-spl.bin u-boot-spl.dtb u-boot.dtb; do
    if [ -f "$image" ]; then
        cp -v "$image" "$OUTPUT_DIR/"
    fi
done

echo "Build successful!"
echo "Images copied to: $OUTPUT_DIR"
