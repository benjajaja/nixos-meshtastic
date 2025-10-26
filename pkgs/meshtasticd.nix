{ lib, stdenv
, fetchzip
, platformio-core
, python3
, scons
, pkg-config
, libusb1
, libgpiod_1
, i2c-tools
, libyaml-cpp
, ulfius
, orcania
, openssl
, bluez
, libuv
, libxkbcommon
, libinput
, xorg
, gnutls
, jansson
, zlib
, libmicrohttpd
, yder
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "meshtasticd";
  version = "2.6.11.60ec05e";

  src = fetchzip {
    url = "https://github.com/meshtastic/firmware/releases/download/v${finalAttrs.version}/meshtasticd-2.6.11.15537.local60ec05e-src.zip";
    hash = "sha256-KixodEnLRXK/yu+N9znAJJaJqpq5wZyw2PYzfZ2vDws=";
    stripRoot = false;
  };

  nativeBuildInputs = [
    platformio-core
    python3
    python3.pkgs.protobuf
    python3.pkgs.grpcio
    scons
    pkg-config
  ];

  buildInputs = [
    libusb1
    libgpiod_1
    i2c-tools
    libyaml-cpp
    ulfius
    orcania
    openssl
    bluez
    libuv
    libxkbcommon
    libinput
    xorg.libX11
    gnutls
    jansson
    zlib
    libmicrohttpd
    yder
  ];

  # PlatformIO environment variables
  # https://docs.platformio.org/en/latest/envvars.html
  # Point to the pre-extracted pio/ directory structure
  PLATFORMIO_CORE_DIR = "pio/core";
  PLATFORMIO_LIBDEPS_DIR = "pio/libdeps";
  PLATFORMIO_PACKAGES_DIR = "pio/packages";
  # Disable features that require internet
  PLATFORMIO_NO_TELEMETRY = "1";
  PIO_NO_GLOBAL_LIB_DIR = "1";

  postUnpack = ''
    # The zip contains a tarball that needs to be extracted
    tar -xf $sourceRoot/meshtasticd_2.6.11.15537~local60ec05e~UNRELEASED.tar.xz -C $sourceRoot --strip-components=0
    # Move contents from extracted meshtasticd/ to source root
    mv $sourceRoot/meshtasticd/* $sourceRoot/meshtasticd/.??* $sourceRoot/ 2>/dev/null || true
    rmdir $sourceRoot/meshtasticd

    # Extract pre-fetched PlatformIO dependencies early
    # This must happen before PlatformIO runs
    tar -xf $sourceRoot/pio.tar -C $sourceRoot
    mkdir -p $sourceRoot/web
    tar -xf $sourceRoot/web.tar -C $sourceRoot/web
    gunzip $sourceRoot/web/ -r

    # Clear PlatformIO cache that might have old URLs
    rm -rf $sourceRoot/pio/core/.cache
    rm -f $sourceRoot/pio/core/appstate.json

    # Replace bundled tool-scons executables with system scons (4.5.2)
    # Keep the original version metadata (4.40502.0 = scons 4.5.2) unchanged
    # System scons version matches exactly - no version mismatch
    rm -f $sourceRoot/pio/packages/tool-scons/scons
    rm -f $sourceRoot/pio/packages/tool-scons/scons-configure-cache
    ln -s ${scons}/bin/scons $sourceRoot/pio/packages/tool-scons/scons
    ln -s ${scons}/bin/scons-configure-cache $sourceRoot/pio/packages/tool-scons/scons-configure-cache 2>/dev/null || true
  '';

  postPatch = ''
    # The pio.tar already contains a pre-built platform-native in pio/core/platforms/native/
    # Instead of downloading it again, just reference it by name "native"
    # Replace the full URL with just "native" to use the pre-installed platform
    substituteInPlace platformio.ini \
      --replace-fail "https://github.com/meshtastic/platform-native/archive/622341c6de8a239704318b10c3dbb00c21a3eab3.zip" \
                     "native"
  '';

  preBuild = ''
    # Dependencies already extracted in postUnpack
  '';

  buildPhase = ''
    runHook preBuild

    # Build with platformio
    platformio run -e native-tft

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp .pio/build/native-tft/program $out/bin/meshtasticd

    mkdir -p $out/share/meshtasticd
    cp bin/config-dist.yaml $out/share/meshtasticd/config.yaml

    runHook postInstall
  '';

  meta = with lib; {
    description = "Meshtastic device firmware for Linux-native devices (meshtasticd)";
    longDescription = ''
      meshtasticd is a Meshtastic daemon for Linux-native devices, utilizing
      portduino to run the firmware under Linux.
      https://meshtastic.org/docs/hardware/devices/linux-native-hardware/
    '';
    homepage = "https://github.com/meshtastic/firmware";
    changelog = "https://github.com/meshtastic/firmware/releases/tag/v${finalAttrs.version}";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    mainProgram = "meshtasticd";
    license = licenses.gpl3Only;
    platforms = [ "x86_64-linux" "aarch64-linux" "armv7l-linux" ];
    maintainers = with maintainers; [ kazenyuk ];
  };
})