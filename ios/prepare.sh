#!/bin/bash
set -e

echo "Starting prepare.sh script..."

# Direct URLs to the release assets
XC_DOWNLOAD_URL="https://github.com/RBeato/flutter_sequencer_plus/releases/download/v1.0.0/xcframeworks.zip"
SRC_DOWNLOAD_URL="https://github.com/RBeato/flutter_sequencer_plus/releases/download/v1.0.0/sources.zip"

# Checksums for verification
EXPECTED_XC="95def6efebafeb6e4780bfae6cf7056c621b15a2ebaa14c30241333c1bc36e71"
EXPECTED_SRC="1efb3b75d4c619cf74fe7e589a58806fa96f63b69596b19dd4e6ca40c16b1d13"

# Function to download a file with retries and checksum verification
download_file() {
  local url=$1
  local dest=$2
  local expected_checksum=$3
  local max_retries=5
  local retry_count=0
  
  # Create directory if it doesn't exist
  mkdir -p "$(dirname "$dest")"
  
  while [ $retry_count -lt $max_retries ]; do
    echo "Downloading $url... (Attempt $((retry_count + 1))/$max_retries)"
    
    # Simple curl command with basic error handling
    echo "Downloading from: $url"
    if curl -L -f -o "$dest" "$url"; then
      # Verify the file was downloaded successfully and has content
      if [ -s "$dest" ]; then
        # Check if this is actually an error page (sometimes GitHub returns HTML for errors)
        if grep -q "<html" "$dest" && grep -q "404" "$dest"; then
          echo "Error: Received 404 page instead of file"
          rm -f "$dest"
          return 1
        fi
        
        # Verify checksum if provided
        if [ -n "$expected_checksum" ]; then
          echo "Verifying checksum..."
          local actual_checksum=$(shasum -a 256 "$dest" | cut -d' ' -f1)
          if [ "$expected_checksum" = "$actual_checksum" ]; then
            echo "✅ Successfully downloaded and verified $dest"
            return 0
          else
            echo "❌ Checksum verification failed for $dest"
            echo "   Expected: $expected_checksum"
            echo "   Actual:   $actual_checksum"
            echo "   File size: $(wc -c < "$dest") bytes"
            rm -f "$dest"
          fi
        else
          echo "✅ Successfully downloaded $dest (no checksum verification)"
          return 0
        fi
      else
        echo "Error: Downloaded file is empty"
        rm -f "$dest"
      fi
    else
      echo "Error: Download failed"
    fi
    
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
      echo "Retrying in 3 seconds..."
      sleep 3
    fi
  done
  
  echo "❌ Failed to download file after $max_retries attempts"
  return 1
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Main script execution
main() {
  echo "=== flutter_sequencer_plus prepare script ==="
  echo "Version: $VERSION"
  echo "Working directory: $(pwd)"
  
  # Check for required commands
  for cmd in curl shasum unzip; do
    if ! command_exists "$cmd"; then
      echo "Error: $cmd is required but not installed"
      exit 1
    fi
  done
  
  # Create necessary directories
  mkdir -p "${PROJECT_DIR}/Flutter/"
  
  # Download xcframeworks
  echo "\n=== Downloading xcframeworks ==="
  download_file \
    "$XC_DOWNLOAD_URL" \
    "${PROJECT_DIR}/Flutter/xcframeworks.zip" \
    "$EXPECTED_XC" || {
      echo "Error: Failed to download xcframeworks"
      exit 1
    }
  
  # Download source files
  echo "\n=== Downloading source files ==="
  download_file \
    "$SRC_DOWNLOAD_URL" \
    "${PROJECT_DIR}/Flutter/sources.zip" \
    "$EXPECTED_SRC" || {
      echo "Error: Failed to download source files"
      exit 1
    }
  
  # Extract files
  echo "\n=== Extracting files ==="
  echo "Extracting xcframeworks..."
  unzip -o "${PROJECT_DIR}/Flutter/xcframeworks.zip" -d "${PROJECT_DIR}/Flutter/"
  
  echo "Extracting source files..."
  unzip -o "${PROJECT_DIR}/Flutter/sources.zip" -d "${PROJECT_DIR}/Flutter/"
  
  echo "\n✅ All files downloaded and extracted successfully!"
}

# Run the main function
main "$@"
        echo "Downloaded file is empty: $dest"
        rm -f "$dest"
      fi
    else
      echo "Failed to download $url"
      rm -f "$dest"
    fi
    
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
      echo "Retrying in 3 seconds..."
      sleep 3
    fi
  done
  
  echo "Failed to download $url after $max_retries attempts"
  return 1
}

verify_checksum() {
  local file=$1
  local expected=$2
  
  if [ ! -f "$file" ]; then
    echo "Error: File not found: $file"
    return 1
  fi
  
  local actual=$(shasum -a 256 "$file" | cut -d' ' -f1)
  if [ "$expected" != "$actual" ]; then
    echo "Checksum mismatch for $file"
    echo "Expected: $expected"
    echo "Actual:   $actual"
    return 1
  fi
  return 0
}

# Ensure script runs from ios directory
echo "Changing to script directory..."
cd "$(dirname "$0")"

# Create necessary directories
echo "Creating directories..."
mkdir -p third_party/sfizz/xcframeworks
mkdir -p third_party/sfizz/src

# Download and unzip xcframeworks if missing
if [ ! -d "third_party/sfizz/xcframeworks/libsfizz.xcframework" ]; then
    echo "Downloading prebuilt xcframeworks..."
    download_file "$REPO_URL/$VERSION/xcframeworks.zip" "xcframeworks.zip" "$EXPECTED_XC"
    
    if [ $? -eq 0 ]; then
        echo "Extracting xcframeworks..."
        unzip -q xcframeworks.zip -d third_party/sfizz
        if [ $? -ne 0 ]; then
            echo "Error: Failed to extract xcframeworks.zip"
            exit 1
        fi
        rm xcframeworks.zip
    else
        echo "Error: Failed to download xcframeworks"
        exit 1
    fi
else
    echo "xcframeworks already exist, skipping download"
fi

# Download and unzip headers if missing
if [ ! -f "third_party/sfizz/src/sfizz.hpp" ]; then
    echo "Downloading sfizz headers..."
    download_file "$REPO_URL/$VERSION/src.zip" "src.zip" "$EXPECTED_SRC"
    
    if [ $? -eq 0 ]; then
        echo "Extracting source files..."
        unzip -q src.zip -d third_party/sfizz
        if [ $? -ne 0 ]; then
            echo "Error: Failed to extract src.zip"
            exit 1
        fi
        rm src.zip
    else
        echo "Error: Failed to download source files"
        exit 1
    fi
else
    echo "Source files already exist, skipping download"
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

echo " sfizz.xcframeworks and headers are ready."
