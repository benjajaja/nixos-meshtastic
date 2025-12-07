#!/usr/bin/env bash
# Build custom Meshtastic firmware with patches
#
# Usage:
#   ./scripts/build-firmware.sh seeed-xiao-s3
#   ./scripts/build-firmware.sh seeed-xiao-s3 RESERVED_FRIED_CHICKEN
#
# This script requires network access to download PlatformIO dependencies.
# It's meant to be run outside of Nix sandbox.

set -euo pipefail

BOARD="${1:-seeed-xiao-s3}"
HARDWARE_MODEL="${2:-}"
VERSION="2.7.15.567b8ea"

echo "=== Meshtastic Firmware Builder ==="
echo "Board: $BOARD"
echo "Version: $VERSION"
[ -n "$HARDWARE_MODEL" ] && echo "Custom Hardware Model: $HARDWARE_MODEL"
echo ""

# Create build directory
BUILD_DIR="${BUILD_DIR:-/tmp/meshtastic-build}"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Download source if not present
if [ ! -d "firmware-$VERSION" ]; then
  echo "Downloading firmware source..."
  curl -L "https://github.com/meshtastic/firmware/archive/refs/tags/v$VERSION.tar.gz" | tar xz
  mv "firmware-$VERSION" "firmware-$VERSION" 2>/dev/null || true
fi

cd "firmware-$VERSION"

# Apply hardware model patch if specified
if [ -n "$HARDWARE_MODEL" ]; then
  echo "Patching hardware model..."

  # Backup original
  cp src/platform/esp32/architecture.h src/platform/esp32/architecture.h.orig

  # Find the board's current hardware model and replace it
  case "$BOARD" in
    *seeed-xiao-s3*|*seeed_xiao_s3*)
      sed -i "s/meshtastic_HardwareModel_SEEED_XIAO_S3/meshtastic_HardwareModel_$HARDWARE_MODEL/g" \
        src/platform/esp32/architecture.h
      ;;
    *heltec-v3*|*heltec_v3*)
      sed -i "s/meshtastic_HardwareModel_HELTEC_V3/meshtastic_HardwareModel_$HARDWARE_MODEL/g" \
        src/platform/esp32/architecture.h
      ;;
    *t-deck*|*t_deck*)
      sed -i "s/meshtastic_HardwareModel_T_DECK/meshtastic_HardwareModel_$HARDWARE_MODEL/g" \
        src/platform/esp32/architecture.h
      ;;
    *)
      echo "Warning: Unknown board pattern, attempting generic replacement"
      UPPER_BOARD=$(echo "$BOARD" | tr '[:lower:]-' '[:upper:]_')
      sed -i "s/meshtastic_HardwareModel_$UPPER_BOARD/meshtastic_HardwareModel_$HARDWARE_MODEL/g" \
        src/platform/esp32/architecture.h
      ;;
  esac

  echo "Patched. Diff:"
  diff src/platform/esp32/architecture.h.orig src/platform/esp32/architecture.h || true
fi

# Check if platformio is available
if ! command -v pio &> /dev/null; then
  echo "Error: PlatformIO not found. Install with: pip install platformio"
  echo "Or enter nix develop shell: nix develop"
  exit 1
fi

echo ""
echo "Building firmware for $BOARD..."
echo "This will download PlatformIO dependencies (requires network access)"
echo ""

pio run -e "$BOARD"

echo ""
echo "=== Build Complete ==="
echo ""
echo "Firmware files:"
ls -la .pio/build/"$BOARD"/*.bin 2>/dev/null || echo "No .bin files found"

OUTPUT_DIR="$BUILD_DIR/output-$BOARD"
mkdir -p "$OUTPUT_DIR"
cp .pio/build/"$BOARD"/*.bin "$OUTPUT_DIR/" 2>/dev/null || true
cp .pio/build/"$BOARD"/*.elf "$OUTPUT_DIR/" 2>/dev/null || true

echo ""
echo "Copied to: $OUTPUT_DIR"
echo ""
echo "To flash, use:"
echo "  esptool.py --port /dev/ttyACM0 erase_flash"
echo "  esptool.py --port /dev/ttyACM0 write_flash 0x0 $OUTPUT_DIR/firmware.bin"
