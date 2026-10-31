
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UBOOT_SRC="$PROJECT_DIR/src/u-boot"
OUTPUT_DIR="$PROJECT_DIR/build/u-boot"

mkdir -p "$OUTPUT_DIR"

for image in MLO u-boot.img; do
    if [[ ! -s "$UBOOT_SRC/$image" ]]; then
        echo "ERROR: Missing build image: $UBOOT_SRC/$image"
        exit 1
    fi

    cp -v "$UBOOT_SRC/$image" "$OUTPUT_DIR/"
done

cd "$OUTPUT_DIR"
sha256sum MLO u-boot.img > SHA256SUMS

echo "Images copied and SHA-256 hashes saved."
sha256sum -c SHA256SUMS

