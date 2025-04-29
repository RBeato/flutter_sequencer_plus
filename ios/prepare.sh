#!/bin/zsh
set -e

echo "Preparing stub libraries for iOS..."

# Create directories if they don't exist
if [ ! -d third_party ]; then
    mkdir -p third_party
fi

cd third_party

# Only clone ios-cmake if needed
if [ ! -d ios-cmake ]; then
    echo "Cloning ios-cmake..."
    git clone https://github.com/leetal/ios-cmake.git
    cd ios-cmake
    git checkout 4.4.1
    cd ..
fi

# For sfizz, we'll create a simpler approach
if [ ! -d sfizz ]; then
    mkdir -p sfizz/build
fi

cd sfizz

# Create empty static libraries as placeholders
if [ ! -f "build/libsfizz_fat.a" ]; then
    echo "Creating empty libsfizz_fat.a for compatibility..."
    mkdir -p build/empty_obj
    cd build/empty_obj
    
    # Create a simple C file with necessary symbols
    cat > placeholder.c << EOF
void sfizz_placeholder() {}
EOF
    
    # Compile for device (arm64)
    xcrun --sdk iphoneos clang -arch arm64 -c placeholder.c -o placeholder_arm64.o
    
    # Compile for simulator (x86_64)
    xcrun --sdk iphonesimulator clang -arch x86_64 -c placeholder.c -o placeholder_x86_64.o
    
    # Create the libraries for each architecture
    xcrun --sdk iphoneos ar rcs ../libsfizz_iphoneos.a placeholder_arm64.o
    xcrun --sdk iphonesimulator ar rcs ../libsfizz_iphonesimulator.a placeholder_x86_64.o
    
    # Create a fat binary
    xcrun lipo -create ../libsfizz_iphoneos.a ../libsfizz_iphonesimulator.a -output ../libsfizz_fat.a
    
    cd ..
    echo "Created placeholder library at $(pwd)/libsfizz_fat.a"
    ls -la libsfizz_fat.a
else
    echo "Library build/libsfizz_fat.a already exists"
fi

echo "prepare.sh script completed successfully"
