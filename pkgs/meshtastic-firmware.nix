{ lib
, stdenvNoCC
, fetchurl
, unzip
, python3
, esptool
, writeShellScriptBin
}:

let
  version = "2.7.22.96dd647";

  # All available platform firmware zips
  platformSources = {
    esp32 = fetchurl {
      url = "https://github.com/meshtastic/firmware/releases/download/v${version}/firmware-esp32-${version}.zip";
      hash = "sha256-9667d797cdb955cfa3210cb17803bef2b7321dac99e52ae96a231e72f92cabec=";
    };
    esp32c3 = fetchurl {
      url = "https://github.com/meshtastic/firmware/releases/download/v${version}/firmware-esp32c3-${version}.zip";
      hash = "sha256-7d7bbbbcb14abf39d792065523793ec04effad7e599e5af800e90c837b15e876=";
    };
    esp32c6 = fetchurl {
      url = "https://github.com/meshtastic/firmware/releases/download/v${version}/firmware-esp32c6-${version}.zip";
      hash = "sha256-2f26e9963bc87566c428f9854d172aecc03451d8560185f48cefa91402092431=";
    };
    esp32s3 = fetchurl {
      url = "https://github.com/meshtastic/firmware/releases/download/v${version}/firmware-esp32s3-${version}.zip";
      hash = "sha256-c356f2070166881c8f5eaf4dc046149f46dfa9b2e7f6ce06f620ae249ffdfa95=";
    };
    nrf52840 = fetchurl {
      url = "https://github.com/meshtastic/firmware/releases/download/v${version}/firmware-nrf52840-${version}.zip";
      hash = "sha256-b1002e06a46b7508920b903327bc4b98694bf4f6b2eeb4d941067cb496a1d843=";
    };
    rp2040 = fetchurl {
      url = "https://github.com/meshtastic/firmware/releases/download/v${version}/firmware-rp2040-${version}.zip";
      hash = "sha256-31d610bbafe5506cdf76f0f30a3c41692e061afd4f952eae3565cbebe3d1e6b1=";
    };
    rp2350 = fetchurl {
      url = "https://github.com/meshtastic/firmware/releases/download/v${version}/firmware-rp2350-${version}.zip";
      hash = "sha256-aa552998dbfe77be612df348f3c7a10fdc14981ce09c28422486ae84a1e577a8=";
    };
    stm32 = fetchurl {
      url = "https://github.com/meshtastic/firmware/releases/download/v${version}/firmware-stm32-${version}.zip";
      hash = "sha256-c2b0d990b18db81e04b86b01b21f25046d5e5c5b21b60c0f9452291beee714da=";
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
