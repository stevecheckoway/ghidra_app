#!/bin/bash

set -e

script_dir=$(dirname "$0")
cache=${GHIDRA_APP_BUILD_CACHE:-"${script_dir}/cache"}

jdk_x64_url='https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.7%2B7/OpenJDK17U-jdk_x64_mac_hotspot_17.0.7_7.tar.gz'
jdk_x64_checksum='50d0e9840113c93916418068ba6c845f1a72ed0dab80a8a1f7977b0e658b65fb'
jdk_x64_home='jdk-17.0.7+7/Contents/Home'

jdk_arm_url='https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.7%2B7/OpenJDK17U-jdk_aarch64_mac_hotspot_17.0.7_7.tar.gz'
jdk_arm_checksum='1d6aeb55b47341e8ec33cc1644d58b88dfdcce17aa003a858baa7460550e6ff9'
jdk_arm_home='jdk-17.0.7+7/Contents/Home'

ghidra_url='https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_10.3_build/ghidra_10.3_PUBLIC_20230510.zip'
ghidra_dist=${ghidra_url##*/}
ghidra_checksum='4e990af9b22be562769bb6ce5d4d609fbb45455a7a2f756167b8cdcdb75887fc'

gradle_url='https://services.gradle.org/distributions/gradle-8.1.1-bin.zip'
gradle_dist=${gradle_url##*/}
gradle_dir="${cache}/${gradle_dist//-bin.zip}"
gradle_checksum='e111cb9948407e26351227dabce49822fb88c37ee72f1d1582a69c68af2e702f'

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

get_gradle() {
  # if gradle-8.1.1 (or whatever version) doesn't exist, download it (if
  # necessary) and unzip it.
  if [[ ! -d "${gradle_dir}" ]]; then
    if [[ ! -f "${cache}/${gradle_dist}" ]]; then
      echo "Downloading Gradle to '${cache}/${gradle_dist}'"
      curl -L -o "${cache}/${gradle_dist}" "${gradle_url}"
    else
      echo "Using cached Gradle from '${cache}/${gradle_dist}'"
    fi

    # Verify the checksum.
    echo "${gradle_checksum}  ${cache}/${gradle_dist}" | shasum --algorithm 256 --check --status

    echo "Installing Gradle in '${gradle_dir}'"
    unzip -d "${cache}" "${cache}/${gradle_dist}"
  fi
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

# https://stackoverflow.com/a/3572105
abspath() {
  if [[ $1 = /* ]]; then
    echo "$1"
  else
    echo "${PWD}/$1"
  fi
}

build_natives() {
  local app=$1 ghidra_version ghidra_dir gradle_bin

  # XXX: Don't duplicate this logic.
  # Figure out the version number.
  [[ "${ghidra_dist}" =~ ^ghidra_([0-9.]+)_([^_]+)_ ]] || exit 1
  ghidra_version=${BASH_REMATCH[1]}
  ghidra_dir="ghidra_${ghidra_version}_${BASH_REMATCH[2]}"

  java_home=$(abspath "${app}/Contents/Resources/${jdk_home}")
  gradle_bin=$(abspath "${gradle_dir}/bin")
  JAVA_HOME="${java_home}" PATH="${gradle_bin}:${java_home}/bin:${PATH}" "${app}/Contents/Resources/${ghidra_dir}/support/buildNatives"
}

normalize_arch() {
  case $1 in
    x86_64|x86-64)
      echo "x86-64"
      ;;
    arm64|aarch64)
      echo "arm64"
      ;;
    *)
      echo "$0: Unsupported architecture '${arch}'" >&2
      exit 1
  esac
}


main() {
  local force app native_arch arch
  native_arch=$(normalize_arch "$(uname -m)")
  arch=${native_arch}
  while getopts "a:fho:" arg; do
    case ${arg} in
      a)
        arch=$(normalize_arch "${OPTARG}")
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
    x86-64)
      jdk_url=${jdk_x64_url}
      jdk_checksum=${jdk_x64_checksum}
      jdk_home=${jdk_x64_home}
      ;;
    arm64)
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
  if [[ $arch = "$native_arch" ]]; then
    echo "Building ${arch} native binaries"
    get_gradle
    build_natives "${app}"
  elif [[ $arch = x86-64 ]]; then
    echo "Using prebuilt native ${arch} binaries; "
  else
    echo "WARNING: native ${arch} binaries have not been built"
    echo "         x86-64 binaries will be used via emulation"
    echo "         This is slower."
  fi
}

main "$@"
