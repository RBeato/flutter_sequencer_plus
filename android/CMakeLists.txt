cmake_minimum_required(VERSION 3.18.1)
project(flutter_sequencer)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Directories
set(ANDROID_DIR ${CMAKE_CURRENT_SOURCE_DIR})
set(IOS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../ios)
set(THIRD_PARTY_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party)

# Include directories
include_directories(
    ${ANDROID_DIR}/src/main/cpp
    ${IOS_DIR}/Classes
    ${ANDROID_DIR}/src/main/cpp/third_party/TinySoundFont
)

# Find system libraries
find_library(log-lib log)
find_library(android-lib android)
find_library(opensl-lib OpenSLES)

# Create main library with TinySoundFont only (minimal build)
add_library(flutter_sequencer SHARED
    # Main plugin file
    ${ANDROID_DIR}/src/main/cpp/Plugin.cpp
    
    # TinySoundFont implementation (header-only library)
    ${ANDROID_DIR}/src/main/cpp/tsf_implementation.cpp
    
    # Shared C++ classes from iOS (cross-platform core)
    ${IOS_DIR}/Classes/CallbackManager/CallbackManager.cpp
    ${IOS_DIR}/Classes/Scheduler/BaseScheduler.cpp
    ${IOS_DIR}/Classes/Scheduler/SchedulerEvent.cpp
    
    # Minimal Android engine (uses OpenSL ES, no Oboe dependency)
    ${ANDROID_DIR}/src/main/cpp/AndroidEngine/AndroidEngine.cpp
)

# Target properties
set_target_properties(flutter_sequencer PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    POSITION_INDEPENDENT_CODE ON
)

# Include directories for the target
target_include_directories(flutter_sequencer PRIVATE
    ${ANDROID_DIR}/src/main/cpp
    ${IOS_DIR}/Classes
    ${IOS_DIR}/Classes/CallbackManager
    ${IOS_DIR}/Classes/Scheduler
    ${IOS_DIR}/Classes/IInstrument
    ${ANDROID_DIR}/src/main/cpp/third_party/TinySoundFont
)

# Compile definitions - minimal build
target_compile_definitions(flutter_sequencer PRIVATE
    ANDROID
    USE_OPENSL_ES=1
    USE_TINYSOUNDFONT=1
    _GNU_SOURCE
    _FILE_OFFSET_BITS=64
)

# Link libraries
target_link_libraries(flutter_sequencer
    ${log-lib}
    ${android-lib}
    ${opensl-lib}
)

# Aggressive compiler optimizations for maximum performance
target_compile_options(flutter_sequencer PRIVATE
    -Wall
    -Wno-unused-parameter
    -fvisibility=hidden
    -fPIC
    -O3  # Maximum optimization
    -ffast-math
    -ftree-vectorize  # Enable auto-vectorization
    -funsafe-math-optimizations  # Allow more aggressive math optimizations
    -fno-signed-zeros
    -fno-trapping-math
    -frename-registers
    -funroll-loops
    $<$<COMPILE_LANGUAGE:CXX>:-fno-exceptions>  # Disable exceptions for performance
    $<$<COMPILE_LANGUAGE:CXX>:-fno-rtti>        # Disable RTTI for performance
)