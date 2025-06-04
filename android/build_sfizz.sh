#!/bin/bash
set -e

# Android NDK path
NDK_PATH="/Users/rbsou/Library/Android/sdk/ndk/26.3.11579264"
TOOLCHAIN="$NDK_PATH/build/cmake/android.toolchain.cmake"

# Build for each architecture
ABIS=("x86_64")

for ABI in "${ABIS[@]}"; do
    echo "Building sfizz for $ABI..."
    
    # Create build directory
    BUILD_DIR="build_android_$ABI"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    # Configure with CMake
    cmake ../third_party/sfizz_source \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_PLATFORM=android-24 \
        -DCMAKE_BUILD_TYPE=Release \
        -DSFIZZ_JACK=OFF \
        -DSFIZZ_RENDER=OFF \
        -DSFIZZ_BENCHMARKS=OFF \
        -DSFIZZ_TESTS=OFF \
        -DSFIZZ_DEMOS=OFF \
        -DSFIZZ_DEVTOOLS=OFF \
        -DSFIZZ_SHARED=ON \
        -DSFIZZ_USE_SNDFILE=OFF \
        -DSFIZZ_STATIC_DEPENDENCIES=ON \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_C_FLAGS="-D_GNU_SOURCE" \
        -DCMAKE_CXX_FLAGS="-D_GNU_SOURCE"
    
    # Build
    cmake --build . --config Release -j8
    
    # Copy the library
    mkdir -p "../third_party/sfizz/lib/$ABI"
    cp library/lib/libsfizz.so "../third_party/sfizz/lib/$ABI/"
    
    cd ..
done

echo "All architectures built successfully!"
ls -la third_party/sfizz/lib/*/libsfizz.so