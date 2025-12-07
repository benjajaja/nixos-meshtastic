{ lib
, writeShellApplication
, esptool
, meshtastic-firmware
}:

writeShellApplication {
  name = "meshtastic-flash";

  runtimeInputs = [ esptool ];

  text = ''
    FIRMWARE_DIR="${meshtastic-firmware}/share/meshtastic-firmware"

    show_help() {
      cat <<EOF
    Usage: meshtastic-flash [OPTIONS] <board-name>

    Flash Meshtastic firmware to an ESP32-based device.

    Options:
      -h, --help           Show this help
      -p, --port PORT      Serial port (default: auto-detect)
      -l, --list           List available boards
      --erase              Erase flash before writing (default for full flash)
      --update             Flash update firmware only (no erase, no littlefs)

    Examples:
      meshtastic-flash seeed-xiao-s3
      meshtastic-flash -p /dev/ttyACM0 heltec-v3
      meshtastic-flash --list

    Available firmware directory: $FIRMWARE_DIR
    EOF
    }

    list_boards() {
      echo "Available boards:"
      echo ""
      for platform in esp32 esp32c3 esp32c6 esp32s3; do
        if [ -d "$FIRMWARE_DIR/$platform" ]; then
          echo "=== $platform ==="
          # shellcheck disable=SC2010
          ls "$FIRMWARE_DIR/$platform/" | grep -E '^firmware-.*\.bin$' | sed 's/firmware-//;s/-2\.7\.15.*\.bin$//' | sort -u
          echo ""
        fi
      done
    }

    # Parse arguments
    PORT=""
    UPDATE_ONLY=false
    LIST=false
    BOARD=""

    while [ $# -gt 0 ]; do
      case "$1" in
        -h|--help)
          show_help
          exit 0
          ;;
        -p|--port)
          PORT="$2"
          shift 2
          ;;
        -l|--list)
          LIST=true
          shift
          ;;
        --update)
          UPDATE_ONLY=true
          shift
          ;;
        --erase)
          # default behavior for full flash
          shift
          ;;
        -*)
          echo "Unknown option: $1" >&2
          exit 1
          ;;
        *)
          BOARD="$1"
          shift
          ;;
      esac
    done

    if [ "$LIST" = true ]; then
      list_boards
      exit 0
    fi

    if [ -z "$BOARD" ]; then
      echo "Error: No board specified" >&2
      echo "Use --list to see available boards" >&2
      exit 1
    fi

    # Find firmware files
    FIRMWARE_BIN=""
    LITTLEFS_BIN=""
    BLEOTA_BIN=""
    PLATFORM=""

    for platform in esp32s3 esp32 esp32c3 esp32c6; do
      if [ -d "$FIRMWARE_DIR/$platform" ]; then
        for f in "$FIRMWARE_DIR/$platform/firmware-$BOARD"-*.bin; do
          if [ -f "$f" ] && [[ ! "$f" =~ -update\.bin$ ]]; then
            FIRMWARE_BIN="$f"
            PLATFORM="$platform"
            break 2
          fi
        done
      fi
    done

    if [ -z "$FIRMWARE_BIN" ]; then
      echo "Error: Firmware not found for board '$BOARD'" >&2
      echo "Use --list to see available boards" >&2
      exit 1
    fi

    # Find littlefs
    for f in "$FIRMWARE_DIR/$PLATFORM/littlefs-$BOARD"-*.bin; do
      if [ -f "$f" ]; then
        LITTLEFS_BIN="$f"
        break
      fi
    done

    # Find bleota
    if [ "$PLATFORM" = "esp32s3" ]; then
      BLEOTA_BIN="$FIRMWARE_DIR/$PLATFORM/bleota-s3.bin"
    elif [ -f "$FIRMWARE_DIR/$PLATFORM/bleota.bin" ]; then
      BLEOTA_BIN="$FIRMWARE_DIR/$PLATFORM/bleota.bin"
    elif [ -f "$FIRMWARE_DIR/$PLATFORM/bleota-c3.bin" ]; then
      BLEOTA_BIN="$FIRMWARE_DIR/$PLATFORM/bleota-c3.bin"
    fi

    echo "Board: $BOARD"
    echo "Platform: $PLATFORM"
    echo "Firmware: $FIRMWARE_BIN"
    [ -n "$LITTLEFS_BIN" ] && echo "LittleFS: $LITTLEFS_BIN"
    [ -n "$BLEOTA_BIN" ] && echo "BLE OTA: $BLEOTA_BIN"
    echo ""

    # Determine offsets based on board (simplified version of device-install.sh logic)
    FIRMWARE_OFFSET=0x00

    # 8MB BigDB boards
    BIGDB_8MB="heltec-v3 heltec-wireless-paper heltec-wireless-tracker heltec-wsl-v3 seeed-xiao-s3 tbeam-s3-core icarus tracksenger heltec_capsule_sensor_v3 heltec-vision-master-e213 heltec-vision-master-e290 heltec-vision-master-t190 crowpanel-esp32s3"
    # 16MB BigDB boards
    BIGDB_16MB="t-deck t-watch-s3 station-g2 m5stack-cores3 heltec-v4 mesh-tab dreamcatcher elecrow-adv ESP32-S3-Pico t-energy-s3 t-eth-elite tlora-pager"
    # 8MB MUIDB boards
    MUIDB_8MB="picomputer-s3 unphone seeed-sensecap-indicator"

    LITTLEFS_OFFSET=0x300000
    OTA_OFFSET=0x260000

    for variant in $BIGDB_8MB; do
      if [[ "$BOARD" == *"$variant"* ]]; then
        LITTLEFS_OFFSET=0x670000
        OTA_OFFSET=0x340000
        break
      fi
    done

    for variant in $MUIDB_8MB; do
      if [[ "$BOARD" == *"$variant"* ]]; then
        LITTLEFS_OFFSET=0x670000
        OTA_OFFSET=0x5D0000
        break
      fi
    done

    for variant in $BIGDB_16MB; do
      if [[ "$BOARD" == *"$variant"* ]]; then
        LITTLEFS_OFFSET=0xc90000
        OTA_OFFSET=0x650000
        break
      fi
    done

    # Build esptool command
    ESPTOOL_ARGS=()
    [ -n "$PORT" ] && ESPTOOL_ARGS+=(--port "$PORT")

    if [ "$UPDATE_ONLY" = true ]; then
      # Update only - just flash the firmware
      UPDATE_BIN=""
      for f in "$FIRMWARE_DIR/$PLATFORM/firmware-$BOARD"-*-update.bin; do
        if [ -f "$f" ]; then
          UPDATE_BIN="$f"
          break
        fi
      done
      if [ -z "$UPDATE_BIN" ]; then
        echo "Error: Update firmware not found for board '$BOARD'" >&2
        exit 1
      fi
      echo "Flashing update firmware..."
      esptool.py "''${ESPTOOL_ARGS[@]}" write_flash $FIRMWARE_OFFSET "$UPDATE_BIN"
    else
      # Full flash
      echo "Erasing flash..."
      esptool.py "''${ESPTOOL_ARGS[@]}" erase_flash

      echo "Flashing firmware at offset $FIRMWARE_OFFSET..."
      esptool.py "''${ESPTOOL_ARGS[@]}" write_flash $FIRMWARE_OFFSET "$FIRMWARE_BIN"

      if [ -n "$BLEOTA_BIN" ] && [ -f "$BLEOTA_BIN" ]; then
        echo "Flashing BLE OTA at offset $OTA_OFFSET..."
        esptool.py "''${ESPTOOL_ARGS[@]}" write_flash "$OTA_OFFSET" "$BLEOTA_BIN"
      fi

      if [ -n "$LITTLEFS_BIN" ] && [ -f "$LITTLEFS_BIN" ]; then
        echo "Flashing LittleFS at offset $LITTLEFS_OFFSET..."
        esptool.py "''${ESPTOOL_ARGS[@]}" write_flash "$LITTLEFS_OFFSET" "$LITTLEFS_BIN"
      fi
    fi

    echo ""
    echo "Done! Device should reboot with new firmware."
  '';

  meta = with lib; {
    description = "Flash Meshtastic firmware to ESP32-based devices";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
    mainProgram = "meshtastic-flash";
  };
}
