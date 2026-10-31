#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UBOOT_SRC="$PROJECT_DIR/src/u-boot"
OUTPUT_DIR="$PROJECT_DIR/build/u-boot"
LOG_DIR="$PROJECT_DIR/logs/build"
LOG_FILE="$LOG_DIR/uboot-build.log"

export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-

mkdir -p "$OUTPUT_DIR" "$LOG_DIR"

if ! command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1; then
    echo "ERROR: Cross-compiler not found."
    exit 1
fi

echo "Configuring U-Boot..."
make -C "$UBOOT_SRC" am335x_evm_defconfig

echo "Building U-Boot..."
make -C "$UBOOT_SRC" -j"$(nproc)" 2>&1 | tee "$LOG_FILE"

echo "Copying generated images..."
for image in MLO u-boot.img u-boot u-boot.bin \
             u-boot-spl.bin u-boot-spl.dtb u-boot.dtb; do
    if [[ -s "$UBOOT_SRC/$image" ]]; then
        cp -v "$UBOOT_SRC/$image" "$OUTPUT_DIR/"
    fi
done

echo "Build successful. Images: $OUTPUT_DIR"

