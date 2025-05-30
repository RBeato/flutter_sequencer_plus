#!/bin/bash
set -e

VERSION="v1.0.0"
REPO_OWNER="RBeato"
REPO_NAME="flutter_sequencer_plus"
BASE_URL="https://github.com/$REPO_OWNER/$REPO_NAME/releases/download"

# Function to download a file
download_file() {
    local url=$1
    local output=$2
    local expected_checksum=$3
    
    echo "Downloading $output..."
    
    # Download the file
    if ! curl -L "$url" -o "$output"; then
        echo "Failed to download $output"
        exit 1
    fi
    
    # Verify checksum
    local actual_checksum=$(shasum -a 256 "$output" | cut -d' ' -f1)
    if [ "$expected_checksum" != "$actual_checksum" ]; then
        echo "Checksum mismatch for $output"
        echo "Expected: $expected_checksum"
        echo "Got:      $actual_checksum"
        exit 1
    fi
}

# Checksums for verification
EXPECTED_XC="95def6efebafeb6e4780bfae6cf7056c621b15a2ebaa14c30241333c1bc36e71"
EXPECTED_SRC="1efb3b75d4c619cf74fe7e589a58806fa96f63b69596b19dd4e6ca40c16b1d13"

# Function to download with authentication
download_file() {
    local url=$1
    local output=$2
    local expected_checksum=$3
    
    echo "Downloading $output..."
    
    # Try with token if available
    if [ -n "$GITHUB_TOKEN" ]; then
        echo "Using GitHub token for authentication"
        curl -H "Authorization: token $GITHUB_TOKEN" -L "$url" -o "$output"
    else
        # Fallback to unauthenticated request
        curl -L "$url" -o "$output"
    fi
    
    if [ $? -ne 0 ]; then
        echo "Failed to download $output"
        if [ -z "$GITHUB_TOKEN" ]; then
            echo "Hint: Set GITHUB_TOKEN environment variable for private repository access"
        fi
        exit 1
    fi
    
    # Verify checksum
    local actual_checksum=$(shasum -a 256 "$output" | cut -d' ' -f1)
    if [ "$expected_checksum" != "$actual_checksum" ]; then
        echo "Checksum mismatch for $output"
        echo "Expected: $expected_checksum"
        echo "Got:      $actual_checksum"
        exit 1
    fi
}

# Ensure script runs from ios directory
cd "$(dirname "$0")"

# Create necessary directories
mkdir -p third_party/sfizz/xcframeworks
mkdir -p third_party/sfizz/src

# Create necessary directories
mkdir -p third_party/sfizz/xcframeworks
mkdir -p third_party/sfizz/src

# Download and unzip xcframeworks if missing
if [ ! -d "third_party/sfizz/xcframeworks/libsfizz.xcframework" ]; then
    echo "Downloading xcframeworks..."
    download_file "$BASE_URL/$VERSION/xcframeworks.zip" "xcframeworks.zip" "$EXPECTED_XC"
    echo "Extracting xcframeworks..."
    unzip -q xcframeworks.zip -d third_party/sfizz
    rm xcframeworks.zip
fi

# Download and unzip headers if missing
if [ ! -f "third_party/sfizz/src/sfizz.hpp" ]; then
    echo "Downloading source files..."
    download_file "$BASE_URL/$VERSION/src.zip" "src.zip" "$EXPECTED_SRC"
    echo "Extracting source files..."
    unzip -q src.zip -d third_party/sfizz
    rm src.zip
fi

# Final verification
echo "Verifying installation..."
if [ ! -d "third_party/sfizz/xcframeworks/libsfizz.xcframework" ]; then
    echo "Error: libsfizz.xcframework not found after installation"
    exit 1
fi

if [ ! -f "third_party/sfizz/src/sfizz.hpp" ]; then
    echo "Error: sfizz.hpp not found after installation"
    exit 1
fi

echo "sfizz.xcframeworks and headers are ready."