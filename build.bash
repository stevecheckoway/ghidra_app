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

ghidra_url='https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_11.0.3_build/ghidra_11.0.3_PUBLIC_20240410.zip'
ghidra_dist=${ghidra_url##*/}
ghidra_checksum='2462a2d0ab11e30f9e907cd3b4aa6b48dd2642f325617e3d922c28e752be6761'

gradle_url='https://services.gradle.org/distributions/gradle-8.1.1-bin.zip'
gradle_dist=${gradle_url##*/}
gradle_checksum='e111cb9948407e26351227dabce49822fb88c37ee72f1d1582a69c68af2e702f'

# Figure out Ghidra's version number.
[[ "${ghidra_dist}" =~ ^ghidra_([0-9.]+)_([^_]+)_ ]] || exit 1
ghidra_version=${BASH_REMATCH[1]}
ghidra_dir="ghidra_${ghidra_version}_${BASH_REMATCH[2]}"

# Print the usage.
usage() {
  cat <<USAGE_EOF
Usage: $0 [OPTION...]

Options:
  -a arch build Ghidra.app for x86-64 or arm64 [default: detect]
  -b      build native executables [default for arm64]
  -B      use prebuilt native executables [default for x86-64]
  -f      force building Ghidra.app even if it already exists
  -h      show this help
  -o app  use 'app' as the output name instead of Ghidra.app
USAGE_EOF
}

# Create the cache directory, if it doesn't already exist.
create_cache() {
  [[ -d "${cache}" ]] || mkdir -p "${cache}"
}

# decompress name URL file_name hash directory
#
# Download the file at URL, save in the cache, and decompress in the directory
decompress() {
  local name=$1 url=$2 file=$3 hash=$4 directory=$5

  if [[ ! -f "${cache}/${file}" ]]; then
    echo " ➤ Downloading ${name} to '${cache}/${file}'"
    curl -L -o "${cache}/${file}" "${url}"
  else
    echo " ➤ Using cached ${name} from '${cache}/${file}'"
  fi

  # Verify the SHA-256 hash.
  echo "${hash}  ${cache}/${file}" | shasum --algorithm 256 --check --status

  echo " ➤ Decompressing ${name} in '${directory}'"
  case ${file} in
    *.tar.gz)
      tar zxf "${cache}/${file}" -C "${directory}"
      ;;
    *.zip)
      unzip -qq "${cache}/${file}" -d "${directory}"
      ;;
    *)
      echo "Unsupported file '$1'" >&2
      exit 1
  esac
}

build_wrapper() {
  local app=$1 arch=$2

  echo "Building the Ghidra wrapper '${app}' for ${arch}"
  mkdir -p "${app}/Contents/MacOS" "${app}/Contents/Resources"

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
  decompress JDK "${jdk_url}" "${jdk_dist}" "${jdk_checksum}" "${app}/Contents/Resources"
  decompress Ghidra "${ghidra_url}" "${ghidra_dist}" "${ghidra_checksum}" "${app}/Contents/Resources"
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
  # On arm64, we can use the JDK we just installed in ${app} to run Gradle
  # regardless of whether ${app} is being built for x86-64 or arm64 due to
  # Rosetta.
  #
  # On x86-64, we need an x86-64 version of the JDK to run Gradle. If we're
  # building an arm64 version of ${app}, then we cannot use the JDK we just
  # installed in ${app}. Instead, we'll need to download the x86-64 JDK.
  local app=$1 arch=$2 gradle_dir target

  echo "Building ${arch} native executables"

  if [[ ${arch} = arm64 && $(uname -m) = x86_64 ]]; then
    java_home="${cache}/${jdk_x64_home}"
    if [[ ! -d "${java_home}" ]]; then
      decompress 'x86-64 JDK' "${jdk_x64_url}" "${jdk_x64_url##*/}" "${jdk_x64_checksum}" "${cache}"
    fi
    echo " ➤ Using the x86-64 JDK to build for arm64"
  else
    echo " ➤ Using the JDK just installed in ${app}"
    java_home="${app}/Contents/Resources/${jdk_home}"
  fi
  java_home=$(abspath "${java_home}")

  gradle_dir="${cache}/${gradle_dist//-bin.zip}"
  if [[ ! -d "${gradle_dir}" ]]; then
    decompress Gradle "${gradle_url}" "${gradle_dist}" "${gradle_checksum}" "${cache}"
  fi

  case ${arch} in
    x86-64)
      target=mac_x86_64
      ;;
    arm64)
      target=mac_arm_64
      ;;
  esac

  JAVA_HOME="${java_home}" PATH="${java_home}/bin:${PATH}" \
    "${gradle_dir}/bin/gradle" \
    --project-dir "${app}/Contents/Resources/${ghidra_dir}/Ghidra" \
    --init-script "${PWD}/init.gradle" \
    "buildNatives_${target}"

  JAVA_HOME="${java_home}" PATH="${java_home}/bin:${PATH}" \
    "${gradle_dir}/bin/gradle" \
    --project-dir "${app}/Contents/Resources/${ghidra_dir}/GPL" \
    --init-script "${PWD}/init.gradle" \
    "buildNatives_${target}"
}

main() {
  local force app arch build_native_executables
  arch=$(uname -m)

  while getopts "a:bBfho:" arg; do
    case ${arg} in
      a)
        arch="${OPTARG}"
        ;;
      b)
        build_native_executables=yes
        ;;
      B)
        build_native_executables=no
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
    x86-64|x86_64)
      arch=x86-64
      jdk_url=${jdk_x64_url}
      jdk_checksum=${jdk_x64_checksum}
      jdk_home=${jdk_x64_home}
      build_native_executables=${build_native_executables:-no}
      ;;
    arm64|aarch64)
      arch=arm64
      jdk_url=${jdk_arm_url}
      jdk_checksum=${jdk_arm_checksum}
      jdk_home=${jdk_arm_home}
      build_native_executables=${build_native_executables:-yes}
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
  build_wrapper "${app}" "${arch}"
  if [[ $build_native_executables = yes ]]; then
    build_natives "${app}" "${arch}"
  elif [[ $arch = x86-64 ]]; then
    echo "Using prebuilt native ${arch} binaries"
  else
    echo "WARNING: Native ${arch} binaries have not been built"
    echo "WARNING: The prebuilt x86-64 binaries will be used via emulation"
    echo "WARNING: This is slower"
  fi
}

main "$@"
