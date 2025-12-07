{ lib
, stdenv
, fetchzip
, platformio-core
, python3
, esptool
, scons
, pkg-config

# Customization options
, board ? "seeed-xiao-s3"           # PlatformIO environment name
, hardwareModel ? null               # Override HW_VENDOR (e.g., "RESERVED_FRIED_CHICKEN")
, variantPatches ? []                # List of patches to apply to variant.h
, extraBuildFlags ? []               # Additional -D flags for the build
}:

let
  version = "2.7.15.567b8ea";

  # Extract version parts
  versionParts = lib.splitString "." version;
  majorMinorPatch = lib.concatStringsSep "." (lib.take 3 versionParts);
  shortHash = lib.elemAt versionParts 3;

  # CI build number (from release filename)
  buildNumber = "21107";

  # Determine platform from board name
  platform =
    if lib.hasInfix "s3" board || lib.hasInfix "S3" board then "esp32s3"
    else if lib.hasInfix "c3" board then "esp32c3"
    else if lib.hasInfix "c6" board then "esp32c6"
    else "esp32";

in stdenv.mkDerivation {
  pname = "meshtastic-firmware-${board}";
  inherit version;

  src = fetchzip {
    url = "https://github.com/meshtastic/firmware/releases/download/v${version}/meshtasticd-${majorMinorPatch}.${buildNumber}.local${shortHash}-src.zip";
    hash = "sha256-j6t+j/rccJomXikDA7LK+I/EScSHfh5AlCTCSw8JRsQ=";
    stripRoot = false;
  };

  nativeBuildInputs = [
    platformio-core
    python3
    python3.pkgs.protobuf
    python3.pkgs.grpcio
    scons
    pkg-config
    esptool
  ];

  # PlatformIO environment variables
  PLATFORMIO_CORE_DIR = "pio/core";
  PLATFORMIO_LIBDEPS_DIR = "pio/libdeps";
  PLATFORMIO_PACKAGES_DIR = "pio/packages";
  PLATFORMIO_NO_TELEMETRY = "1";
  PIO_NO_GLOBAL_LIB_DIR = "1";

  postUnpack = let
    tarballName = "meshtasticd_${majorMinorPatch}.${buildNumber}~local${shortHash}~UNRELEASED.tar.xz";
  in ''
    # Extract nested tarball
    tar -xf $sourceRoot/${tarballName} -C $sourceRoot --strip-components=0
    mv $sourceRoot/meshtasticd/* $sourceRoot/meshtasticd/.??* $sourceRoot/ 2>/dev/null || true
    rmdir $sourceRoot/meshtasticd

    # Extract PlatformIO dependencies
    tar -xf $sourceRoot/pio.tar -C $sourceRoot
    mkdir -p $sourceRoot/web
    tar -xf $sourceRoot/web.tar -C $sourceRoot/web
    gunzip $sourceRoot/web/ -r

    # Clean PlatformIO cache
    rm -rf $sourceRoot/pio/core/.cache
    rm -f $sourceRoot/pio/core/appstate.json

    # Replace bundled scons with system scons
    rm -f $sourceRoot/pio/packages/tool-scons/scons
    rm -f $sourceRoot/pio/packages/tool-scons/scons-configure-cache
    ln -s ${scons}/bin/scons $sourceRoot/pio/packages/tool-scons/scons
    ln -s ${scons}/bin/scons-configure-cache $sourceRoot/pio/packages/tool-scons/scons-configure-cache 2>/dev/null || true
  '';

  postPatch = ''
    # Patch platform-native URL to use local
    substituteInPlace arch/portduino/portduino.ini \
      --replace-fail "https://github.com/meshtastic/platform-native/archive/f566d364204416cdbf298e349213f7d551f793d9.zip" \
                     "native"

    # Patch library commit hashes to match bundled versions
    substituteInPlace platformio.ini \
      --replace-quiet "meshtastic/ArduinoThread/archive/b841b0415721f1341ea41cccfb4adccfaf951567" \
                      "meshtastic/ArduinoThread/archive/7c3ee9e1951551b949763b1f5280f8db1fa4068d"

    ${lib.optionalString (hardwareModel != null) ''
      # Patch hardware model for the board
      echo "Patching hardware model to: ${hardwareModel}"

      # Find the board's define name (e.g., SEEED_XIAO_S3)
      BOARD_DEFINE=$(grep -E '^\s*-D\s+[A-Z_]+\s*$' variants/${platform}/*${lib.replaceStrings ["-"] ["_"] board}*/platformio.ini 2>/dev/null | sed 's/.*-D\s*\([A-Z_]*\).*/\1/' | head -1 || echo "")

      if [ -n "$BOARD_DEFINE" ]; then
        echo "Found board define: $BOARD_DEFINE"
        substituteInPlace src/platform/esp32/architecture.h \
          --replace-fail "#elif defined($BOARD_DEFINE)" \
"#elif defined($BOARD_DEFINE)
#define HW_VENDOR meshtastic_HardwareModel_${hardwareModel}
#elif defined(${hardwareModel}_DISABLED_ORIGINAL_$BOARD_DEFINE)"
      else
        echo "Warning: Could not find board define, trying direct replacement"
        # Fallback: try to find and replace directly
        substituteInPlace src/platform/esp32/architecture.h \
          --replace-quiet "meshtastic_HardwareModel_SEEED_XIAO_S3" \
                          "meshtastic_HardwareModel_${hardwareModel}" || true
      fi
    ''}

    # Apply any custom variant patches
    ${lib.concatMapStringsSep "\n" (patch: ''
      echo "Applying variant patch..."
      patch -p1 < ${patch}
    '') variantPatches}
  '';

  buildPhase = ''
    runHook preBuild

    echo "Building firmware for board: ${board} (platform: ${platform})"
    ${lib.optionalString (hardwareModel != null) ''
      echo "Using custom hardware model: ${hardwareModel}"
    ''}

    # Build with platformio
    platformio run -e ${board} ${lib.concatMapStringsSep " " (flag: "-e PLATFORMIO_BUILD_FLAGS=\"${flag}\"") extraBuildFlags}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/firmware

    # Copy built firmware files
    cp .pio/build/${board}/*.bin $out/firmware/ 2>/dev/null || true
    cp .pio/build/${board}/*.elf $out/firmware/ 2>/dev/null || true

    # Generate littlefs if partition table exists
    if [ -f .pio/build/${board}/littlefs.bin ]; then
      cp .pio/build/${board}/littlefs.bin $out/firmware/
    fi

    # Copy bootloader and partition table if they exist
    for f in bootloader partitions; do
      if [ -f .pio/build/${board}/$f.bin ]; then
        cp .pio/build/${board}/$f.bin $out/firmware/
      fi
    done

    # Create a flash script
    cat > $out/bin/flash-${board} << 'FLASH_EOF'
#!/usr/bin/env bash
set -e
FIRMWARE_DIR="$out/firmware"
PORT="''${1:-}"

if [ -z "$PORT" ]; then
  echo "Usage: flash-${board} <port>"
  echo "Example: flash-${board} /dev/ttyACM0"
  exit 1
fi

echo "Flashing ${board} firmware to $PORT..."

# Erase and flash
esptool.py --port "$PORT" erase_flash
esptool.py --port "$PORT" write_flash 0x0 "$FIRMWARE_DIR/firmware.bin"

echo "Done!"
FLASH_EOF
    chmod +x $out/bin/flash-${board}
    substituteInPlace $out/bin/flash-${board} --replace-fail '$out' "$out"

    runHook postInstall
  '';

  passthru = {
    inherit board platform hardwareModel;
  };

  meta = with lib; {
    description = "Custom Meshtastic firmware for ${board}" + lib.optionalString (hardwareModel != null) " (HW: ${hardwareModel})";
    homepage = "https://github.com/meshtastic/firmware";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
