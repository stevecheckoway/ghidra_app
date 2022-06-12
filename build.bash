#!/bin/bash

set -e

script_dir=$(dirname "$0")
cache=${GHIDRA_APP_BUILD_CACHE:-"${script_dir}/cache"}

jdk_x64_url='https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.14.1%2B1/OpenJDK11U-jdk_x64_mac_hotspot_11.0.14.1_1.tar.gz'
jdk_x64_checksum='8c69808f5d9d209b195575e979de0e43cdf5d0f1acec1853a569601fe2c1f743'
jdk_x64_home='jdk-11.0.14.1+1/Contents/Home'
jdk_arm_url='https://download.bell-sw.com/java/11.0.14.1+1/bellsoft-jdk11.0.14.1+1-macos-aarch64.zip'
jdk_arm_checksum='c0271a4702b546f757861708f41950ab4d46edfee656af6262825d2a971b2368'
jdk_arm_home='jdk-11.0.14.1.jdk'

ghidra_url='https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_10.1.4_build/ghidra_10.1.4_PUBLIC_20220519.zip'
ghidra_dist=${ghidra_url##*/}
ghidra_checksum='91556c77c7b00f376ca101a6026c0d079efbf24a35b09daaf80bda897318c1f1'

# Print the usage.
usage() {
  cat <<USAGE_EOF
Usage: $0 [OPTION...]

Options:
  -a arch include the JDK for x86-64 or arm64 [default: detect]
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
  if [[ ! -f "${cache}/${jdk_dist}" ]]; then
    echo "Downloading the JDK to '${cache}/${jdk_dist}'"
    curl -L -o "${cache}/${jdk_dist}" "${jdk_url}"
  else
    echo "Using the cached JDK from '${cache}/${jdk_dist}'"
  fi

  # Verify the checksum.
  echo "${jdk_checksum}  ${cache}/${jdk_dist}" | shasum --algorithm 256 --check --status
}

# Download Ghidra, if we don't already have it.
get_ghidra() {
  if [[ ! -f "${cache}/${ghidra_dist}" ]]; then
    echo "Downloading Ghidra to '${cache}/${ghidra_dist}'"
    curl -L -o "${cache}/${ghidra_dist}" "${ghidra_url}"
  else
    echo "Using cached Ghidra from '${cache}/${ghidra_dist}'"
  fi

  # Verify the checksum.
  echo "${ghidra_checksum}  ${cache}/${ghidra_dist}" | shasum --algorithm 256 --check --status
}

# Decompress the archive in $1 to ${app}/Contents/Resources.
decompress() {
  case $1 in
    *.tar.gz)
      tar zxf "$1" -C "${app}/Contents/Resources"
      ;;
    *.zip)
      unzip -qq "$1" -d "${app}/Contents/Resources"
      ;;
    *)
      echo "Unsupported file '$1'" >&2
      exit 1
  esac
}

build_wrapper() {
  local app=$1 arch=$2 ghidra_version ghidra_dir

  echo "Building the Ghidra wrapper '${app}' for ${arch}"
  mkdir -p "${app}/Contents/MacOS" "${app}/Contents/Resources"

  # Figure out the version number.
  [[ "${ghidra_dist}" =~ ^ghidra_([0-9.]+)_([^_]+)_ ]] || exit 1
  ghidra_version=${BASH_REMATCH[1]}
  ghidra_dir="ghidra_${ghidra_version}_${BASH_REMATCH[2]}"

  # Create the Info.plist.
  cat >"${app}/Contents/Info.plist" <<INFO_EOF
{
  "CFBundleDisplayName": "$(basename "${app}" .app)",
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
export JAVA_HOME="\${app}/Resources/${jdk_home}"
export PATH="\${JAVA_HOME}/bin:\${PATH}"
exec "\${app}/Resources/${ghidra_dir}/ghidraRun"
GHIDRA_EOF

  chmod +x "${app}/Contents/MacOS/ghidra"

  # Copy the icon file.
  cp "${script_dir}/ghidra.icns" "${app}/Contents/Resources"

  # Unzip the JDK and Ghidra into the Resources directory.
  decompress "${cache}/${jdk_dist}"
  decompress "${cache}/${ghidra_dist}"
}

main() {
  local force app arch
  arch=$(uname -m)
  while getopts "a:fho:" arg; do
    case ${arg} in
      a)
        arch=${OPTARG}
        ;;
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
  case ${arch} in
    x86_64|x86-64)
      jdk_url=${jdk_x64_url}
      jdk_checksum=${jdk_x64_checksum}
      jdk_home=${jdk_x64_home}
      ;;
    arm64|aarch64)
      jdk_url=${jdk_arm_url}
      jdk_checksum=${jdk_arm_checksum}
      jdk_home=${jdk_arm_home}
      ;;
    *)
      echo "$0: Unsupported architecture '${arch}'" >&2
      exit 1
  esac
  jdk_dist=${jdk_url##*/}

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
  build_wrapper "${app}" "${arch}"
}

main "$@"
