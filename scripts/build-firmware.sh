#!/usr/bin/env bash
# Build custom Meshtastic firmware for Seeed XIAO S3 with:
# - Custom hardware model (RESERVED_FRIED_CHICKEN / Muzi Base)
# - Battery sensing on GPIO2 (for solar-battery combos)
# - ESP32 internal temperature sensor
#
# Usage:
#   ./scripts/build-firmware.sh
#   ./scripts/build-firmware.sh --clean   # Force clean rebuild
#
# Hardware setup for battery sensing (6V max battery):
#   Battery+ ──[100kΩ]──┬──[100kΩ]── GND
#                       │
#                    GPIO2 (A1 pad on XIAO)
#
# This script requires network access to download PlatformIO dependencies.

set -euo pipefail

BOARD="seeed-xiao-s3"
HARDWARE_MODEL="RESERVED_FRIED_CHICKEN"
BATTERY_PIN="2"
ADC_MULTIPLIER="2.0"
VERSION="2.7.15.567b8ea"
CLEAN=false

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --clean)
      CLEAN=true
      ;;
    --help|-h)
      echo "Usage: $0 [--clean]"
      echo "  --clean   Force clean rebuild"
      exit 0
      ;;
  esac
done

echo "=== Custom Meshtastic Firmware Builder ==="
echo "Board: $BOARD"
echo "Version: $VERSION"
echo "Hardware Model: $HARDWARE_MODEL (Muzi Base)"
echo "Battery Pin: GPIO$BATTERY_PIN (ADC multiplier: $ADC_MULTIPLIER)"
echo "Internal Temp: Enabled"
echo ""

# Create build directory
BUILD_DIR="${BUILD_DIR:-/tmp/meshtastic-build}"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Clean if requested
if [ "$CLEAN" = true ] && [ -d "firmware-$VERSION" ]; then
  echo "Cleaning previous build..."
  rm -rf "firmware-$VERSION"
fi

# Download source if not present
if [ ! -d "firmware-$VERSION" ]; then
  echo "Downloading firmware source..."
  curl -L "https://github.com/meshtastic/firmware/archive/refs/tags/v$VERSION.tar.gz" | tar xz
fi

cd "firmware-$VERSION"

# Find variant directory
VARIANT_DIR="variants/esp32s3/seeed_xiao_s3"
if [ ! -d "$VARIANT_DIR" ]; then
  echo "Error: Could not find variant directory: $VARIANT_DIR"
  exit 1
fi

echo "Variant directory: $VARIANT_DIR"

# ============================================
# PATCH 1: Battery sensing on GPIO2
# ============================================
echo ""
echo "Applying patch: Battery sensing on GPIO$BATTERY_PIN..."

# Apply battery pin changes
sed -i "s/#define BATTERY_PIN -1/#define BATTERY_PIN $BATTERY_PIN/" "$VARIANT_DIR/variant.h"
sed -i "s/#define ADC_CHANNEL ADC1_GPIO1_CHANNEL/#define ADC_CHANNEL ADC1_GPIO${BATTERY_PIN}_CHANNEL/" "$VARIANT_DIR/variant.h"

# Add ADC_MULTIPLIER after BATTERY_SENSE_RESOLUTION_BITS
if ! grep -q "#define ADC_MULTIPLIER" "$VARIANT_DIR/variant.h"; then
  sed -i "/#define BATTERY_SENSE_RESOLUTION_BITS/a #define ADC_MULTIPLIER $ADC_MULTIPLIER" "$VARIANT_DIR/variant.h"
fi

echo "Battery sensing configured:"
grep -E "BATTERY_PIN|ADC_CHANNEL|ADC_MULTIPLIER" "$VARIANT_DIR/variant.h"

# ============================================
# PATCH 2: Hardware model to FRIED_CHICKEN
# ============================================
echo ""
echo "Applying patch: Hardware model -> $HARDWARE_MODEL..."

sed -i "s/meshtastic_HardwareModel_SEEED_XIAO_S3/meshtastic_HardwareModel_$HARDWARE_MODEL/g" \
  src/platform/esp32/architecture.h

echo "Hardware model patched"

# ============================================
# PATCH 3: Firmware Edition -> DIY_EDITION
# ============================================
echo ""
echo "Applying patch: Firmware edition -> DIY_EDITION..."

# Add define to variant.h
if ! grep -q "USERPREFS_FIRMWARE_EDITION" "$VARIANT_DIR/variant.h"; then
  sed -i '1i #define USERPREFS_FIRMWARE_EDITION meshtastic_FirmwareEdition_DIY_EDITION' "$VARIANT_DIR/variant.h"
fi

echo "Firmware edition patched"

# ============================================
# PATCH 4: Internal temperature sensor
# ============================================
echo "Applying patch: Internal temperature sensor..."

ENVTEL_FILE="src/modules/Telemetry/EnvironmentTelemetry.cpp"

if ! grep -q "temperatureRead" "$ENVTEL_FILE"; then
  sed -i '/return valid && hasSensor;/i \
#ifdef ARDUINO_ARCH_ESP32\
    if (!m->variant.environment_metrics.has_temperature) {\
        m->variant.environment_metrics.has_temperature = true;\
        m->variant.environment_metrics.temperature = temperatureRead();\
        hasSensor = true;\
    }\
#endif' "$ENVTEL_FILE"
fi

echo "Internal temperature sensor patched"

# ============================================
# BUILD
# ============================================

# Check if platformio is available
if ! command -v pio &> /dev/null; then
  echo ""
  echo "Error: PlatformIO not found. Install with: pip install platformio"
  echo "Or enter nix develop shell: nix develop"
  exit 1
fi

echo ""
echo "Building firmware..."
echo "This will download PlatformIO dependencies (requires network access)"
echo ""

pio run -e "$BOARD"

echo ""
echo "=== Build Complete ==="

OUTPUT_DIR="$BUILD_DIR/output-$BOARD"
mkdir -p "$OUTPUT_DIR"
cp .pio/build/"$BOARD"/*.bin "$OUTPUT_DIR/" 2>/dev/null || true
cp .pio/build/"$BOARD"/*.elf "$OUTPUT_DIR/" 2>/dev/null || true
cp "$VARIANT_DIR/variant.h" "$OUTPUT_DIR/variant.h.patched"

echo ""
echo "Firmware files:"
ls -la "$OUTPUT_DIR"/*.bin 2>/dev/null

echo ""
echo "=== Flash Instructions ==="
echo ""
echo "1. Put device in bootloader mode:"
echo "   - Hold BOOT button"
echo "   - Press RESET (or replug USB)"
echo "   - Release BOOT"
echo ""
echo "2. Flash:"
echo "   esptool.py --port /dev/ttyACM0 write_flash 0x0 $OUTPUT_DIR/firmware.factory.bin"
echo ""
echo "=== Features Enabled ==="
echo "- Hardware ID: Muzi Base ($HARDWARE_MODEL)"
echo "- Firmware Edition: DIY_EDITION"
echo "- Battery sensing: GPIO$BATTERY_PIN (wire 100k+100k divider from battery)"
echo "- Internal temp: ESP32 chip temperature as environment sensor"
