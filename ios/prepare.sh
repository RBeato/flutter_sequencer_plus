#!/bin/bash
set -e

VERSION="v1.0.0"
REPO_URL="https://github.com/RBeato/flutter_sequencer_plus/releases/download"

EXPECTED_XC="95def6efebafeb6e4780bfae6cf7056c621b15a2ebaa14c30241333c1bc36e71"
EXPECTED_SRC="1efb3b75d4c619cf74fe7e589a58806fa96f63b69596b19dd4e6ca40c16b1d13"

verify_checksum() {
  local file=$1
  local expected=$2
  local actual=$(shasum -a 256 $file | cut -d' ' -f1)
  if [ "$expected" != "$actual" ]; then
    echo "Checksum mismatch for $file"
    exit 1
  fi
}

# Ensure script runs from ios directory
cd "$(dirname "$0")"

mkdir -p third_party/sfizz/xcframeworks
mkdir -p third_party/sfizz/src

# Download and unzip xcframeworks if missing
if [ ! -d "third_party/sfizz/xcframeworks/libsfizz.xcframework" ]; then
    echo "Downloading prebuilt xcframeworks..."
    curl -L "$REPO_URL/$VERSION/xcframeworks.zip" -o xcframeworks.zip
    verify_checksum xcframeworks.zip "$EXPECTED_XC"
    unzip -q xcframeworks.zip -d third_party/sfizz
    rm xcframeworks.zip
fi

# Download and unzip headers if missing
if [ ! -f "third_party/sfizz/src/sfizz.hpp" ]; then
    echo "Downloading sfizz headers..."
    curl -L "$REPO_URL/$VERSION/src.zip" -o src.zip
    verify_checksum src.zip "$EXPECTED_SRC"
    unzip -q src.zip -d third_party/sfizz
    rm src.zip
fi

echo "sfizz.xcframeworks and headers are ready."
