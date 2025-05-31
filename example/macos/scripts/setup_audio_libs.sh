#!/bin/bash

# Create Frameworks directory if it doesn't exist
mkdir -p "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"

# List of required libraries
LIBS=(
    "libsndfile.1.dylib"
    "libvorbis.0.dylib"
    "libvorbisenc.2.dylib"
    "libogg.0.dylib"
    "libFLAC.8.dylib"
    "libopus.0.dylib"
    "libmpg123.0.dylib"
)

# Copy each library and fix its paths
for lib in "${LIBS[@]}"; do
    # Find the library in Homebrew's Cellar
    LIB_PATH=$(find /opt/homebrew/Cellar -name "${lib}" | head -n 1)
    
    if [ -z "$LIB_PATH" ]; then
        echo "Warning: ${lib} not found in Homebrew Cellar"
        continue
    fi
    
    # Copy the library
    cp -f "${LIB_PATH}" "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/"
    
    # Get the library filename
    LIB_NAME=$(basename "${LIB_PATH}")
    
    # Fix the library's ID
    install_name_tool -id "@rpath/${LIB_NAME}" "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/${LIB_NAME}"
    
    # Fix the library's dependencies
    for dep in "${LIBS[@]}"; do
        DEP_NAME=$(basename "${dep}")
        install_name_tool -change "/opt/homebrew/opt/${dep%%/*}/lib/${DEP_NAME}" "@rpath/${DEP_NAME}" \
            "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/${LIB_NAME}" || true
    done
    
    # Add to the list of libraries to sign
    if [ -z "${CODESIGN_LIBS}" ]; then
        CODESIGN_LIBS="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/${LIB_NAME}"
    else
        CODESIGN_LIBS="${CODESIGN_LIBS} ${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/${LIB_NAME}"
    fi
done

# Sign all libraries if code signing is enabled
if [ "${CODE_SIGNING_REQUIRED}" == "YES" ] && [ -n "${CODESIGN_LIBS}" ]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" ${CODESIGN_LIBS}
fi
