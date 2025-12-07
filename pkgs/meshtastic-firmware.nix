{ lib
, stdenvNoCC
, fetchurl
, unzip
, python3
, esptool
, writeShellScriptBin
}:

let
  version = "2.7.15.567b8ea";

  # All available platform firmware zips
  platformSources = {
    esp32 = fetchurl {
      url = "https://github.com/meshtastic/firmware/releases/download/v${version}/firmware-esp32-${version}.zip";
      hash = "sha256-fuc/4fNRFWpTyZ6bNOJaMYJxdF70YXVA0lLUmnWiWY4=";
    };
    esp32c3 = fetchurl {
      url = "https://github.com/meshtastic/firmware/releases/download/v${version}/firmware-esp32c3-${version}.zip";
      hash = "sha256-14k/3TFJreYwOaQw5lMPZQv1DZAKH0V4rmY+/OjxZxs=";
    };
    esp32c6 = fetchurl {
      url = "https://github.com/meshtastic/firmware/releases/download/v${version}/firmware-esp32c6-${version}.zip";
      hash = "sha256-oeDar+cNK7j4hB8LkVkpZhj9mwJztC2CR+/ICi/sKuE=";
    };
    esp32s3 = fetchurl {
      url = "https://github.com/meshtastic/firmware/releases/download/v${version}/firmware-esp32s3-${version}.zip";
      hash = "sha256-rDn4tlF/63v2ptFzxG/KgIaAcj6LxFRO2zGF4xOYrNw=";
    };
    nrf52840 = fetchurl {
      url = "https://github.com/meshtastic/firmware/releases/download/v${version}/firmware-nrf52840-${version}.zip";
      hash = "sha256-9O9LlXUZICvsymxZn4kDPkjDXBAVMjcLKy+GGyuFk6M=";
    };
    rp2040 = fetchurl {
      url = "https://github.com/meshtastic/firmware/releases/download/v${version}/firmware-rp2040-${version}.zip";
      hash = "sha256-9iYSzulWF/a9yUnv6/yt+ajX96e7KRINayJrwooRXjs=";
    };
    rp2350 = fetchurl {
      url = "https://github.com/meshtastic/firmware/releases/download/v${version}/firmware-rp2350-${version}.zip";
      hash = "sha256-q+ud6CjEeCHJ/0Akq9ZYFzKXjKvB0noanR3C2oV6Fyg=";
    };
    stm32 = fetchurl {
      url = "https://github.com/meshtastic/firmware/releases/download/v${version}/firmware-stm32-${version}.zip";
      hash = "sha256-JCaklJ9pXaezZyUcZ+AzMY2p05rCf19XhxizIBumNO8=";
    };
  };

in stdenvNoCC.mkDerivation {
  pname = "meshtastic-firmware";
  inherit version;

  srcs = lib.attrValues platformSources;

  sourceRoot = ".";

  nativeBuildInputs = [ unzip ];

  unpackPhase = ''
    runHook preUnpack

    # Unpack each platform zip into its own directory
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: src: ''
      mkdir -p ${name}
      unzip -q ${src} -d ${name}
    '') platformSources)}

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/meshtastic-firmware

    # Copy all platforms
    ${lib.concatMapStringsSep "\n" (name: ''
      cp -r ${name} $out/share/meshtastic-firmware/
    '') (lib.attrNames platformSources)}

    # Copy device-install.sh from one of the archives (they're all the same)
    cp esp32s3/device-install.sh $out/share/meshtastic-firmware/ 2>/dev/null || true
    chmod +x $out/share/meshtastic-firmware/device-install.sh 2>/dev/null || true

    runHook postInstall
  '';

  passthru = {
    inherit platformSources;
  };

  meta = with lib; {
    description = "Pre-built Meshtastic firmware binaries for various platforms";
    homepage = "https://github.com/meshtastic/firmware";
    changelog = "https://github.com/meshtastic/firmware/releases/tag/v${version}";
    license = licenses.gpl3Only;
    platforms = platforms.all;
    maintainers = with maintainers; [ kazenyuk ];
  };
}
