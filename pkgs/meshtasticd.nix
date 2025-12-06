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
  version = "2.7.15.567b8ea";

  # CI build number from release filename (not derivable from version tag)
  passthru.buildNumber = "21107";

  src = let
    # version = X.Y.Z.hash, extract parts
    versionParts = lib.splitString "." finalAttrs.version;
    majorMinorPatch = lib.concatStringsSep "." (lib.take 3 versionParts);
    shortHash = lib.elemAt versionParts 3;
  in fetchzip {
    url = "https://github.com/meshtastic/firmware/releases/download/v${finalAttrs.version}/meshtasticd-${majorMinorPatch}.${finalAttrs.passthru.buildNumber}.local${shortHash}-src.zip";
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

  postUnpack = let
    versionParts = lib.splitString "." finalAttrs.version;
    majorMinorPatch = lib.concatStringsSep "." (lib.take 3 versionParts);
    shortHash = lib.elemAt versionParts 3;
    tarballName = "meshtasticd_${majorMinorPatch}.${finalAttrs.passthru.buildNumber}~local${shortHash}~UNRELEASED.tar.xz";
  in ''
    # The zip contains a tarball that needs to be extracted
    tar -xf $sourceRoot/${tarballName} -C $sourceRoot --strip-components=0
    # Move contents from extracted meshtasticd/ to source root
    mv $sourceRoot/meshtasticd/* $sourceRoot/meshtasticd/.??* $sourceRoot/ 2>/dev/null || true
    rmdir $sourceRoot/meshtasticd

    # Extract pre-fetched PlatformIO platform/tools from src package
    tar -xf $sourceRoot/pio.tar -C $sourceRoot
    mkdir -p $sourceRoot/web
    tar -xf $sourceRoot/web.tar -C $sourceRoot/web
    gunzip $sourceRoot/web/ -r

    # Clear PlatformIO cache
    rm -rf $sourceRoot/pio/core/.cache
    rm -f $sourceRoot/pio/core/appstate.json

    # Replace bundled tool-scons with system scons
    rm -f $sourceRoot/pio/packages/tool-scons/scons
    rm -f $sourceRoot/pio/packages/tool-scons/scons-configure-cache
    ln -s ${scons}/bin/scons $sourceRoot/pio/packages/tool-scons/scons
    ln -s ${scons}/bin/scons-configure-cache $sourceRoot/pio/packages/tool-scons/scons-configure-cache 2>/dev/null || true
  '';

  postPatch = ''
    # Use pre-installed platform-native from pio/ instead of downloading
    substituteInPlace arch/portduino/portduino.ini \
      --replace-fail "https://github.com/meshtastic/platform-native/archive/f566d364204416cdbf298e349213f7d551f793d9.zip" \
                     "native"

    # Patch platformio.ini to use the exact commit hashes that are bundled in pio.tar
    # This ensures PlatformIO recognizes pre-installed libs and doesn't try to download
    substituteInPlace platformio.ini \
      --replace-quiet "meshtastic/ArduinoThread/archive/b841b0415721f1341ea41cccfb4adccfaf951567" \
                      "meshtastic/ArduinoThread/archive/7c3ee9e1951551b949763b1f5280f8db1fa4068d"
  '';

  preBuild = ''
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
    sourceProvenance = with sourceTypes; [ fromSource ];
    mainProgram = "meshtasticd";
    license = licenses.gpl3Only;
    platforms = [ "x86_64-linux" "aarch64-linux" "armv7l-linux" ];
    maintainers = with maintainers; [ kazenyuk ];
  };
})