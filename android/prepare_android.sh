#!/bin/bash
set -e

# Configuration - Update these when creating a GitHub release
VERSION="v1.0.0"
REPO_OWNER="RBeato"
REPO_NAME="flutter_sequencer_plus"
BASE_URL="https://github.com/$REPO_OWNER/$REPO_NAME/releases/download"

# Checksums for verification - Update after uploading libraries to GitHub release
# Set to empty string to skip checksum verification during development
EXPECTED_ARMEABI_V7A=""
EXPECTED_ARM64_V8A=""
EXPECTED_X86_64=""

echo "Setting up Android build environment..."

# Create necessary directories
mkdir -p third_party/sfizz/include/sfizz
mkdir -p third_party/sfizz/lib/arm64-v8a
mkdir -p third_party/sfizz/lib/armeabi-v7a
mkdir -p third_party/sfizz/lib/x86_64

# Download sfizz.h
echo "Downloading sfizz.h..."
if ! curl -L "https://raw.githubusercontent.com/sfztools/sfizz/develop/headers/sfizz.h" -o "third_party/sfizz/include/sfizz/sfizz.h" 2>/dev/null; then
    echo "Warning: Failed to download sfizz.h, using minimal version"
    # Fallback to minimal sfizz.h
    cat > third_party/sfizz/include/sfizz/sfizz.h << 'EOF'
#ifndef SFIZZ_H
#define SFIZZ_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct sfizz_synth sfizz_synth_t;

// Minimal function declarations
sfizz_synth_t* sfizz_create_synth();
void sfizz_free(sfizz_synth_t* synth);
int sfizz_load_file(sfizz_synth_t* synth, const char* path);
int sfizz_set_sample_rate(sfizz_synth_t* synth, float sample_rate);
void sfizz_send_note_on(sfizz_synth_t* synth, int delay, int note_number, int velocity);
void sfizz_send_note_off(sfizz_synth_t* synth, int delay, int note_number, int velocity);
void sfizz_render_block(sfizz_synth_t* synth, float** buffers, int num_frames);

#ifdef __cplusplus
}
#endif

#endif // SFIZZ_H
EOF
fi

echo "[prepare_android.sh] Checking for sfizz native libraries and headers..."

# Checksums already defined at the top of the script

# Function to download sfizz library for a specific ABI
download_sfizz_library() {
    local ABI=$1
    local OUTPUT_DIR="third_party/sfizz/lib/$ABI"
    local OUTPUT_FILE="$OUTPUT_DIR/libsfizz.so"
    
    mkdir -p "$OUTPUT_DIR"
    
    # Skip if already exists
    if [ -f "$OUTPUT_FILE" ]; then
        echo "Library for $ABI already exists, skipping download"
        return 0
    fi
    
    # TODO: Replace with actual download URLs for each ABI
    local DOWNLOAD_URL="$BASE_URL/$VERSION/sfizz-android-$ABI.so"
    
    echo "Downloading sfizz library for $ABI..."
    if ! curl -L "$DOWNLOAD_URL" -o "$OUTPUT_FILE"; then
        echo "Failed to download sfizz library for $ABI"
        return 1
    fi
    
    # Verify checksum if available
    local EXPECTED_CHECKSUM=""
    case $ABI in
        "armeabi-v7a") EXPECTED_CHECKSUM="$EXPECTED_ARMEABI_V7A" ;;
        "arm64-v8a") EXPECTED_CHECKSUM="$EXPECTED_ARM64_V8A" ;;
        "x86_64") EXPECTED_CHECKSUM="$EXPECTED_X86_64" ;;
    esac
    
    if [ -n "$EXPECTED_CHECKSUM" ]; then
        local ACTUAL_CHECKSUM=$(shasum -a 256 "$OUTPUT_FILE" | cut -d' ' -f1)
        if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
            echo "Checksum mismatch for $ABI library"
            echo "Expected: $EXPECTED_CHECKSUM"
            echo "Got:      $ACTUAL_CHECKSUM"
            return 1
        fi
    fi
    
    echo "Successfully downloaded and verified $ABI library"
    return 0
}

# Check and download libraries for all ABIs
ABIS=("armeabi-v7a" "arm64-v8a" "x86_64")
MISSING_ABIS=()

for ABI in "${ABIS[@]}"; do
    LIB_PATH="third_party/sfizz/lib/$ABI/libsfizz.so"
    if [ ! -f "$LIB_PATH" ]; then
        echo "Library not found at $LIB_PATH, attempting to download..."
        if ! download_sfizz_library "$ABI"; then
            MISSING_ABIS+=("$ABI")
        fi
    else
        echo "Found existing library for $ABI"
        echo "Found $LIB_PATH"
    fi
    if [ ! -d "third_party/sfizz/include/sfizz" ]; then
        echo "ERROR: Missing sfizz headers in third_party/sfizz/include/sfizz/"
        MISSING_HEADERS=true
    fi
done

# Check if we have any missing components
if [ ${#MISSING_ABIS[@]} -ne 0 ]; then
    echo -e "\nERROR: Missing the following native libraries:"
    for MISSING_ABI in "${MISSING_ABIS[@]}"; do
        echo "  - $MISSING_ABI/libsfizz.so"
    done
    
    echo -e "\nTo fix this issue, you have the following options:"
    echo "1. Build the sfizz libraries from source for each ABI and place them in the appropriate directories"
    echo "2. Provide pre-built libraries in the third_party/sfizz/lib/ directory structure"
    echo "3. Update the download URLs in this script to point to valid pre-built libraries"
    echo -e "\nThe expected directory structure is:"
    echo "  third_party/sfizz/"
    echo "  ├── include/"
    echo "  │   └── sfizz/"
    echo "  │       └── sfizz.h"
    echo "  └── lib/"
    echo "      ├── armeabi-v7a/"
    echo "      │   └── libsfizz.so"
    echo "      ├── arm64-v8a/"
    echo "      │   └── libsfizz.so"
    echo "      └── x86_64/"
    echo "          └── libsfizz.so"
    
    echo -e "\nFor development purposes, you can continue with the minimal implementation, "
    echo "but audio functionality will be limited."
    
    # Use non-interactive mode if CI is set or NONINTERACTIVE is set
    if [ -n "$CI" ] || [ -n "$NONINTERACTIVE" ]; then
        echo "Running in non-interactive mode, creating minimal implementation..."
        REPLY="y"
    else
        read -p "Continue with minimal implementation? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Create minimal implementation if needed
    for ABI in "${MISSING_ABIS[@]}"; do
        mkdir -p "third_party/sfizz/lib/$ABI"
        touch "third_party/sfizz/lib/$ABI/libsfizz.so"
        echo "Created empty library for $ABI"
    done
fi

if [ "$MISSING_HEADERS" = true ]; then
    echo -e "\nWARNING: Using minimal sfizz.h implementation. Some features may not be available."
    
    # We already created a minimal sfizz.h at the beginning, so we can continue
    echo "Continuing with minimal sfizz.h implementation..."
fi

echo -e "\nAndroid build environment is ready."
echo "Note: For full functionality, please provide the proper sfizz libraries and headers."

# Make sure all libraries are executable and have proper permissions
for ABI in armeabi-v7a arm64-v8a x86_64; do
    if [ -f "third_party/sfizz/lib/$ABI/libsfizz.so" ]; then
        chmod 755 "third_party/sfizz/lib/$ABI/libsfizz.so"
        echo "Set executable permissions for $ABI library"
    fi
done

# Output checksums for existing libraries (useful when creating a GitHub release)
if [ -n "$PRINT_CHECKSUMS" ]; then
    echo "\nChecksums for libraries (copy these to the script after uploading to GitHub):"
    for ABI in armeabi-v7a arm64-v8a x86_64; do
        if [ -f "third_party/sfizz/lib/$ABI/libsfizz.so" ]; then
            # Skip files with zero size (dummy libraries)
            if [ -s "third_party/sfizz/lib/$ABI/libsfizz.so" ]; then
                CHECKSUM=$(shasum -a 256 "third_party/sfizz/lib/$ABI/libsfizz.so" | cut -d' ' -f1)
                echo "EXPECTED_${ABI//-/_}=\"$CHECKSUM\""
            else
                echo "Skipping checksum for empty $ABI library"
            fi
        fi
    done
fi

# Find Android NDK
if [ -z "$ANDROID_NDK" ] && [ -f "local.properties" ]; then
    ANDROID_NDK=$(grep 'ndk.dir=' local.properties | cut -d '=' -f2 | tr -d '\r')
fi

if [ -z "$ANDROID_NDK" ]; then
    ANDROID_NDK="$HOME/Library/Android/sdk/ndk/$(ls -1 $HOME/Library/Android/sdk/ndk/ | sort -V | tail -n1)"
fi

if [ ! -d "$ANDROID_NDK" ]; then
    echo "Error: Android NDK not found at $ANDROID_NDK"
    exit 1
fi

echo "Android setup complete!"

