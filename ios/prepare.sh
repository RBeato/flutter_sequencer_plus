#!/bin/zsh

if [ ! -d third_party ]; then
    mkdir third_party
fi
cd third_party

if [ ! -d ios-cmake ]; then
    git clone https://github.com/leetal/ios-cmake.git
    cd ios-cmake
    git checkout 8dfe972
    cd ..
fi

if [ ! -d oboe ]; then
    git clone https://github.com/google/oboe.git
    cd oboe
    git checkout 1.6.1
    cd ..
fi

if [ ! -d sfizz ]; then
    git clone --recurse-submodules https://github.com/sfztools/sfizz.git
    cd sfizz
    git checkout 3a9ae00
    cd ..
fi

if [ ! -d TSF ]; then
    mkdir TSF
    cd TSF
    curl -L https://github.com/schellingb/TinySoundFont/raw/master/tsf.h > tsf.h
    curl -L https://github.com/schellingb/TinySoundFont/raw/master/tml.h > tml.h
    curl -L https://github.com/schellingb/TinySoundFont/raw/master/tfs.h > tfs.h
    cd ..
fi

cd ../Classes
if [ ! -d third_party ]; then
    ln -s ../third_party third_party
fi

cd ../..
if [ -L third_party ]; then
    rm third_party
fi

if [ ! -d build ]; then
    mkdir build
fi

ln -s ios/third_party third_party

cd sfizz

if [ ! -d build ]; then
    mkdir build
fi

cd build

# Generate XCode project for Sfizz
cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DSFIZZ_JACK=OFF \
    -DSFIZZ_RENDER=OFF \
    -DSFIZZ_LV2=OFF \
    -DSFIZZ_LV2_UI=OFF \
    -DSFIZZ_VST=OFF \
    -DSFIZZ_AU=OFF \
    -DSFIZZ_SHARED=OFF \
    -DCMAKE_TOOLCHAIN_FILE=../../ios-cmake/ios.toolchain.cmake \
    -DAPPLE_APPKIT_LIBRARY=/System/Library/Frameworks/AppKit.framework \
    -DAPPLE_CARBON_LIBRARY=/System/Library/Frameworks/Carbon.framework \
    -DAPPLE_COCOA_LIBRARY=/System/Library/Frameworks/Cocoa.framework \
    -DAPPLE_OPENGL_LIBRARY=/System/Library/Frameworks/OpenGL.framework \
    -DPLATFORM=OS64COMBINED \
    -DENABLE_BITCODE=OFF \
    -DENABLE_ARC=ON \
    -DENABLE_VISIBILITY=OFF \
    -G Xcode \
    ..

xcodebuild -project sfizz.xcodeproj -scheme ALL_BUILD -xcconfig ../../../overrides.xcconfig -configuration Release -destination "generic/platform=iOS" -destination "generic/platform=iOS Simulator" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO

# Create fat libraries
deviceLibs=(**/Release-iphoneos/*.a);
simulatorLibs=(**/Release-iphonesimulator/*.a);

libtool -static -o libsfizz_all_iphoneos.a $deviceLibs
libtool -static -o libsfizz_all_iphonesimulator.a $simulatorLibs
lipo \
    -create libsfizz_all_iphoneos.a libsfizz_all_iphonesimulator.a \
    -output libsfizz_fat.a
