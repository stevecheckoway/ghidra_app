#!/bin/bash

set -e

script_dir=$(dirname "$0")
cache=${GHIDRA_APP_BUILD_CACHE:-"${script_dir}/cache"}

jdk_url='https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.7%2B10/OpenJDK11U-jdk_x64_mac_hotspot_11.0.7_10.tar.gz'
jdk_tar=$(basename "${jdk_url}")
jdk_checksum='0ab1e15e8bd1916423960e91b932d2b17f4c15b02dbdf9fa30e9423280d9e5cc'

ghidra_url='https://ghidra-sre.org/ghidra_9.1.2_PUBLIC_20200212.zip'
ghidra_zip=$(basename "${ghidra_url}")
ghidra_checksum='ebe3fa4e1afd7d97650990b27777bb78bd0427e8e70c1d0ee042aeb52decac61'

# Print the usage.
usage() {
  cat <<USAGE_EOF
Usage: $0 [OPTION...]

Options:
  -f      force building Ghidra.app even if it already exists
  -h      show this help
  -o app  use 'app' as the output name
USAGE_EOF
}

# Create the cache directory, if it doesn't already exist.
create_cache() {
  [[ -d "${cache}" ]] || mkdir -p "${cache}"
}

# Download the JDK if we don't already have it.
get_jdk() {
  if [[ ! -f "${cache}/${jdk_tar}" ]]; then
    echo "Downloading the JDK to '${cache}/${jdk_tar}'"
    curl -L -o "${cache}/${jdk_tar}" "${jdk_url}"
  else
    echo "Using the cached JDK from '${cache}/${jdk_tar}'"
  fi

  # Verify the checksum.
  echo "${jdk_checksum}  ${cache}/${jdk_tar}" | shasum --algorithm 256 --check --status
}

# Download Ghidra, if we don't already have it.
get_ghidra() {
  if [[ ! -f "${cache}/${ghidra_zip}" ]]; then
    echo "Downloading Ghidra to '${cache}/${ghidra_zip}'"
    curl -L -o "${cache}/${ghidra_zip}" "${ghidra_url}"
  else
    echo "Using cached Ghidra from '${cache}/${jdk_tar}'"
  fi

  # Verify the checksum.
  echo "${ghidra_checksum}  ${cache}/${ghidra_zip}" | shasum --algorithm 256 --check --status
}

build_wrapper() {
  local app=$1 ghidra_version ghidra_dir

  echo "Building the Ghidra wrapper '${app}'"
  mkdir -p "${app}/Contents/MacOS" "${app}/Contents/Resources"

  # Figure out the version number.
  [[ "${ghidra_zip}" =~ ^ghidra_([0-9.]+)_([^_]+)_ ]] || exit 1
  ghidra_version=${BASH_REMATCH[1]}
  ghidra_dir="ghidra_${ghidra_version}_${BASH_REMATCH[2]}"

  # Create the Info.plist.
  cat >"${app}/Contents/Info.plist" <<INFO_EOF
{
  "CFBundleDisplayName": "Ghidra",
  "CFBundleDevelopmentRegion": "English",
  "CFBundleExecutable": "ghidra",
  "CFBundleIconFile": "ghidra",
  "CFBundleIdentifier": "net.checkoway.ghidra_app",
  "CFBundleInfoDictionaryVersion": "6.0",
  "CFBundleName": "Ghidra",
  "CFBundlePackageType": "APPL",
  "CFBundleShortVersionString": "${ghidra_version}",
  "CFBundleVersion": "${ghidra_version}",
  "LSMinimumSystemVersion": "10.10",
}
INFO_EOF

  # Convert the plist from JSON to the binary format.
  plutil -convert binary1 "${app}/Contents/Info.plist"

  # Create the ghidra wrapper script.
  cat >"${app}/Contents/MacOS/ghidra" <<GHIDRA_EOF
#!/bin/bash
app="\${0/MacOS\/ghidra}"
export JAVA_HOME="\${app}/Resources/jdk-11.0.7+10/Contents/Home"
export PATH="\${JAVA_HOME}/bin:\${PATH}"
exec "\${app}/Resources/${ghidra_dir}/ghidraRun"
GHIDRA_EOF

  chmod +x "${app}/Contents/MacOS/ghidra"

  # Copy the icon file.
  cp "${script_dir}/ghidra.icns" "${app}/Contents/Resources"

  # Untar the JDK into the Resources directory.
  tar Jxf "${cache}/${jdk_tar}" -C "${app}/Contents/Resources"

  # Unzip Ghidra
  unzip -qq "${cache}/${ghidra_zip}" -d "${app}/Contents/Resources"
}

main() {
  local force app

  while getopts "fho:" arg; do
    case ${arg} in
      f)
        force=yes
        ;;
      h)
        usage
        exit 0
        ;;
      o)
        app=${OPTARG}
        ;;
      *)
        usage >&2
        exit 1
    esac
  done

  app=${app:-Ghidra.app}

  if [[ -e ${app} ]]; then
    if [[ ${force} = yes ]]; then
      rm -rf "${app}"
    else
      echo "$0: '${app}' already exists; use -f to force building anyway" >&2
      exit 1
    fi
  fi

  create_cache
  get_jdk
  get_ghidra
  build_wrapper "${app}"
}

main "$@"
