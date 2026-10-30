#!/usr/bin/env bash

set -uo pipefail

PROJECT_DIR="$HOME/Workspace/EmbeddLinux/Project"
UBOOT_SRC="$PROJECT_DIR/src/u-boot"
BUILD_DIR="$PROJECT_DIR/build/u-boot-work"
OUTPUT_DIR="$PROJECT_DIR/build/u-boot"
LOG_DIR="$PROJECT_DIR/logs/build"
LOG_FILE="$LOG_DIR/uboot-clean-build.log"

ARCH="arm"
CROSS_COMPILE="arm-linux-gnueabihf-"
DEFCONFIG="am335x_evm_defconfig"

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR" "$LOG_DIR"

if ! command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1; then
    echo "ERROR: Cross-compiler ${CROSS_COMPILE}gcc not found."
    exit 1
fi

if ! git -C "$UBOOT_SRC" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: U-Boot source repository not found: $UBOOT_SRC"
    exit 1
fi

{
    echo "=== U-Boot reproducible build ==="
    date -Is
    echo "Source: $UBOOT_SRC"
    echo "Tag: $(git -C "$UBOOT_SRC" describe --tags --always)"
    echo "Commit: $(git -C "$UBOOT_SRC" rev-parse HEAD)"
    echo "Compiler: $("${CROSS_COMPILE}gcc" --version | head -n 1)"
    echo "Architecture: $ARCH"
    echo "Defconfig: $DEFCONFIG"
    echo "Build directory: $BUILD_DIR"
    echo
} > "$LOG_FILE"

echo "Configuring U-Boot..."

if ! make -C "$UBOOT_SRC" O="$BUILD_DIR" \
    ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" \
    "$DEFCONFIG" 2>&1 | tee -a "$LOG_FILE"; then
    echo "ERROR: U-Boot configuration failed. See $LOG_FILE"
    exit 1
fi

echo "Building U-Boot..."

if ! make -C "$UBOOT_SRC" O="$BUILD_DIR" \
    ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" \
    -j"$(nproc)" 2>&1 | tee -a "$LOG_FILE"; then
    echo "ERROR: U-Boot build failed. Existing staged artifacts were preserved."
    exit 1
fi

for image in MLO u-boot.img; do
    if [[ ! -s "$BUILD_DIR/$image" ]]; then
        echo "ERROR: Required artifact missing or empty: $BUILD_DIR/$image"
        exit 1
    fi
done

echo "Build succeeded. Staging artifacts..."

for image in MLO u-boot.img u-boot u-boot.bin \
             u-boot-spl.bin u-boot-spl.dtb u-boot.dtb; do
    if [[ -s "$BUILD_DIR/$image" ]]; then
        cp -v "$BUILD_DIR/$image" "$OUTPUT_DIR/"
    fi
done

sha256sum "$OUTPUT_DIR/MLO" "$OUTPUT_DIR/u-boot.img" \
    > "$OUTPUT_DIR/SHA256SUMS"

{
    echo
    echo "Build exit status: 0"
    echo "Artifacts: $OUTPUT_DIR"
    echo "Checksums: $OUTPUT_DIR/SHA256SUMS"
} | tee -a "$LOG_FILE"

echo "Build successful."
