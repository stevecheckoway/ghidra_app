#!/bin/bash

set -e

script_dir=$(dirname "$0")
cache=${GHIDRA_APP_BUILD_CACHE:-"${script_dir}/cache"}

jdk_x64_url='https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.4%2B7/OpenJDK21U-jdk_x64_mac_hotspot_21.0.4_7.tar.gz'
jdk_x64_checksum='e368e5de7111aa88e6bbabeff6f4c040772b57fb279cc4e197b51654085bbc18'
jdk_x64_home='jdk-21.0.4+7/Contents/Home'

jdk_arm_url='https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.4%2B7/OpenJDK21U-jdk_aarch64_mac_hotspot_21.0.4_7.tar.gz'
jdk_arm_checksum='dcf69a21601d9b1b25454bbad4f0f32784bb42cdbe4063492e15a851b74cb61e'
jdk_arm_home='jdk-21.0.4+7/Contents/Home'

ghidra_url='https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_11.2_build/ghidra_11.2_PUBLIC_20240926.zip'
ghidra_dist=${ghidra_url##*/}
ghidra_checksum='a98fe01038fe8791c54b121ede545ea799d26358794d7c2ac09fa3f5054f3cdc'

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
  -n      use the latest Ghidra version
  -o app  use 'app' as the output name instead of Ghidra.app
USAGE_EOF
}

# Create the cache directory, if it doesn't already exist.
create_cache() {
  [[ -d "${cache}" ]] || mkdir -p "${cache}"
}

clear_old_ghidra_versions() {
  # List all Ghidra files in the cache directory
  files=("${cache}"/ghidra_*.zip)

  # Function to extract version numbers from filenames
  extract_version() {
      echo "$1" | awk -F '[_.]' '{print $2"."$3"."$4}'
  }

  # Find the latest version
  latest_version="0.0.0"
  latest_file=""

  for file in "${files[@]}"; do
      version=$(extract_version "$file")
      if [ "$(printf '%s\n' "$latest_version" "$version" | sort -V | tail -n 1)" = "$version" ]; then
          latest_version="$version"
          latest_file="$file"
      fi
  done

  # Delete all files except the latest version
  for file in "${files[@]}"; do
      if [ "$file" != "$latest_file" ]; then
          rm "$file"
          echo "Deleted $file"
      fi
  done

  echo "Kept latest version: $latest_file"
}

fetch_latest_ghidra() {
  # Fetch the latest release JSON using curl
  GHIDRA_RELEASES_URL="https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/latest"
  release_json=$(curl -s $GHIDRA_RELEASES_URL)
  # Extract the browser download URL using awk and sed
  ghidra_url=$(echo "$release_json" | awk -F '"' '/"browser_download_url":/ {print $4}' | head -n 1)
  ghidra_dist=${ghidra_url##*/}
  # Extract the SHA-256 checksum from the release body using sed
  ghidra_checksum=$(echo "$release_json" | sed -n 's/.*SHA-256: `\([0-9a-fA-F]\{64\}\)`.*/\1/p')
  [[ "${ghidra_dist}" =~ ^ghidra_([0-9.]+)_([^_]+)_ ]] || exit 1
  ghidra_version=${BASH_REMATCH[1]}
  ghidra_dir="ghidra_${ghidra_version}_${BASH_REMATCH[2]}"
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
# This file doesn't exist anymore  
cp  "${PWD}/settings.gradle" "${app}/Contents/Resources/${ghidra_dir}/Ghidra"

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
  local force app arch build_native_executables latest
  arch=$(uname -m)

  while getopts "a:bBfhno:" arg; do
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
      n)
        latest=yes
        echo "Using latest version"
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
  clear_old_ghidra_versions

  if [ "$latest" = "yes" ]; then
    echo "Getting latest Ghidra release"
    fetch_latest_ghidra
  fi

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
