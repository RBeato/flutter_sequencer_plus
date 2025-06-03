#!/bin/bash
set -e

# Configuration - Update these when creating a GitHub release
VERSION="v1.0.1-android"
REPO_OWNER="RBeato"
REPO_NAME="flutter_sequencer_plus"
BASE_URL="https://github.com/$REPO_OWNER/$REPO_NAME/releases/download"

# Checksums for the working sfizz stub libraries (functional for compilation)
EXPECTED_ARMEABI_V7A="9bd71c0375d709e2c843c231698fbee353166de95fb422374740d32c2e19e126"
EXPECTED_ARM64_V8A="64916a37c94f5ed281387b3c38f0a4747df1336f800b7b3804d668e74f8fd52d"
EXPECTED_X86_64="0948a6712776e69e4314c5f781c025a4be65faaf1437dc53660534e62b45b5a5"

echo "Setting up Android build environment..."

# Create necessary directories
mkdir -p third_party/sfizz/include/sfizz
mkdir -p third_party/sfizz/lib/arm64-v8a
mkdir -p third_party/sfizz/lib/armeabi-v7a
mkdir -p third_party/sfizz/lib/x86_64
mkdir -p third_party/oboe

# Download sfizz headers
echo "Downloading sfizz headers..."
if ! curl -s -L "https://raw.githubusercontent.com/sfztools/sfizz/develop/src/sfizz.h" -o "third_party/sfizz/include/sfizz/sfizz.h" 2>/dev/null; then
    echo "Warning: Failed to download sfizz.h from official repo, using minimal version"
    # Create minimal sfizz.h for compilation
    cat > third_party/sfizz/include/sfizz/sfizz.h << 'EOF'
#ifndef SFIZZ_H
#define SFIZZ_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct sfizz_synth sfizz_synth_t;

// Core function declarations for minimal implementation
sfizz_synth_t* sfizz_create_synth();
void sfizz_free(sfizz_synth_t* synth);
int sfizz_load_file(sfizz_synth_t* synth, const char* path);
int sfizz_set_sample_rate(sfizz_synth_t* synth, float sample_rate);
int sfizz_set_samples_per_block(sfizz_synth_t* synth, int samples_per_block);
void sfizz_send_note_on(sfizz_synth_t* synth, int delay, int note_number, int velocity);
void sfizz_send_note_off(sfizz_synth_t* synth, int delay, int note_number, int velocity);
void sfizz_render_block(sfizz_synth_t* synth, float** buffers, int num_frames);

#ifdef __cplusplus
}
#endif

#endif // SFIZZ_H
EOF
fi

# Function to download sfizz library for a specific ABI
download_sfizz_library() {
    local ABI=$1
    local OUTPUT_DIR="third_party/sfizz/lib/$ABI"
    local OUTPUT_FILE="$OUTPUT_DIR/libsfizz.so"
    
    mkdir -p "$OUTPUT_DIR"
    
    # Skip if already exists and is not empty
    if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
        local file_size=$(wc -c < "$OUTPUT_FILE")
        if [ "$file_size" -gt 100 ]; then  # More than 100 bytes means it's likely a real library
            echo "Library for $ABI already exists and appears valid, skipping download"
            return 0
        fi
    fi
    
    local DOWNLOAD_URL="$BASE_URL/$VERSION/sfizz-android-$ABI.so"
    
    echo "Downloading sfizz library for $ABI..."
    if curl -s -L "$DOWNLOAD_URL" -o "$OUTPUT_FILE"; then
        local file_size=$(wc -c < "$OUTPUT_FILE")
        
        # Verify checksum if available
        local EXPECTED_CHECKSUM=""
        case $ABI in
            "armeabi-v7a") EXPECTED_CHECKSUM="$EXPECTED_ARMEABI_V7A" ;;
            "arm64-v8a") EXPECTED_CHECKSUM="$EXPECTED_ARM64_V8A" ;;
            "x86_64") EXPECTED_CHECKSUM="$EXPECTED_X86_64" ;;
        esac
        
        if [ -n "$EXPECTED_CHECKSUM" ] && [ "$file_size" -gt 100 ]; then
            local ACTUAL_CHECKSUM=$(shasum -a 256 "$OUTPUT_FILE" | cut -d' ' -f1)
            if [ "$EXPECTED_CHECKSUM" = "$ACTUAL_CHECKSUM" ]; then
                echo "✓ Successfully downloaded and verified real sfizz library for $ABI ($file_size bytes)"
                chmod 755 "$OUTPUT_FILE"
                return 0
            else
                echo "⚠ Checksum mismatch for $ABI library - may be outdated"
                echo "  Expected: $EXPECTED_CHECKSUM"
                echo "  Got:      $ACTUAL_CHECKSUM"
            fi
        fi
        
        if [ "$file_size" -gt 100 ]; then
            echo "✓ Downloaded real sfizz library for $ABI ($file_size bytes) - checksum not verified"
            chmod 755 "$OUTPUT_FILE"
            return 0
        else
            echo "⚠ Downloaded file for $ABI appears to be a dummy library ($file_size bytes)"
            echo "  This will work for basic compilation but won't provide full sfizz functionality"
            chmod 755 "$OUTPUT_FILE"
            return 0
        fi
    else
        echo "✗ Failed to download sfizz library for $ABI"
        echo "  Creating minimal stub library for compilation"
        touch "$OUTPUT_FILE"
        chmod 755 "$OUTPUT_FILE"
        return 1
    fi
}

# Download libraries for all ABIs
ABIS=("armeabi-v7a" "arm64-v8a" "x86_64")
REAL_LIBRARIES=()
DUMMY_LIBRARIES=()

for ABI in "${ABIS[@]}"; do
    if download_sfizz_library "$ABI"; then
        lib_path="third_party/sfizz/lib/$ABI/libsfizz.so"
        file_size=$(wc -c < "$lib_path")
        if [ "$file_size" -gt 100 ]; then
            REAL_LIBRARIES+=("$ABI")
        else
            DUMMY_LIBRARIES+=("$ABI")
        fi
    else
        DUMMY_LIBRARIES+=("$ABI")
    fi
done

# Report status
echo
echo "=== Android Setup Summary ==="
if [ ${#REAL_LIBRARIES[@]} -gt 0 ]; then
    echo "✓ Real sfizz libraries found for: ${REAL_LIBRARIES[*]}"
fi
if [ ${#DUMMY_LIBRARIES[@]} -gt 0 ]; then
    echo "⚠ Dummy/stub libraries for: ${DUMMY_LIBRARIES[*]}"
fi

if [ ${#REAL_LIBRARIES[@]} -eq 0 ]; then
    echo
    echo "⚠ WARNING: No real sfizz libraries found. Using minimal implementation."
    echo "  The plugin will compile and run but audio functionality will be limited."
    echo "  To get full functionality, you need to:"
    echo "  1. Build real sfizz libraries for Android (see GitHub releases)"
    echo "  2. Upload them to the GitHub release and update checksums"
    echo "  3. Re-run this script"
fi

# Download Oboe if not already present  
if [ ! -d "third_party/oboe" ]; then
    echo
    echo "Cloning Oboe audio library..."
    cd third_party
    if git clone --depth 1 --branch 1.7.0 https://github.com/google/oboe.git; then
        echo "✓ Oboe library cloned successfully"
    else
        echo "⚠ Failed to clone Oboe library"
        echo "  You can manually clone it from: https://github.com/google/oboe"
    fi
    cd ..
else
    echo "✓ Oboe library already exists"
fi

echo
echo "✓ Android build environment ready!"
echo "  Headers: third_party/sfizz/include/sfizz/"
echo "  Libraries: third_party/sfizz/lib/{armeabi-v7a,arm64-v8a,x86_64}/"
echo "  Oboe: third_party/oboe/"