cmake_minimum_required(VERSION 3.18.1)

# Add after cmake_minimum_required but before project()
include_directories(${ANDROID_NDK}/sysroot/usr/include)
include_directories(${ANDROID_NDK}/sysroot/usr/include/${ANDROID_TOOLCHAIN_NAME})

project(Sequencer VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# First create the target
add_library(flutter_sequencer SHARED)

# Configure third-party dependencies
set(OBOE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/oboe)
set(TSF_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/TinySoundFont)
set(SFIZZ_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/sfizz)

# Download dependencies if they don't exist
if(NOT EXISTS ${OBOE_DIR})
    execute_process(
        COMMAND git clone https://github.com/google/oboe.git ${OBOE_DIR}
        COMMAND git -C ${OBOE_DIR} checkout 06ec23e4f6bc00ba7eea9b84e299f9200a598838
    )
endif()

# Add Oboe
add_subdirectory(${OBOE_DIR})

# Include directories
target_include_directories(flutter_sequencer
    PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../ios/Classes/CallbackManager
    ${CMAKE_CURRENT_SOURCE_DIR}/../ios/Classes/Scheduler
    ${CMAKE_CURRENT_SOURCE_DIR}/../ios/Classes/IInstrument
    ${CMAKE_CURRENT_SOURCE_DIR}/src/main/cpp
    ${OBOE_DIR}/include
    ${TSF_DIR}
    ${SFIZZ_DIR}/include
)

# Source files
target_sources(flutter_sequencer
    PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../ios/Classes/CallbackManager/CallbackManager.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../ios/Classes/Scheduler/BaseScheduler.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../ios/Classes/Scheduler/SchedulerEvent.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/main/cpp/AndroidEngine/AndroidEngine.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/main/cpp/Plugin.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/src/main/cpp/AudioEngine.cpp
)

# Find Android dependencies
find_library(android-lib android)
find_library(log-lib log)

# Link libraries
target_link_libraries(flutter_sequencer
    PRIVATE
    ${android-lib}
    ${log-lib}
    oboe
)

# Set compile options
target_compile_options(flutter_sequencer
    PRIVATE
    -Wall
    -Wextra
    -fexceptions
    -frtti
)

# Set compile definitions for different build types
target_compile_definitions(flutter_sequencer
    PRIVATE
    $<$<CONFIG:Debug>:DEBUG>
    $<$<CONFIG:Release>:NDEBUG>
)

# Ensure we have Dart_PostCObject_DL available
target_compile_definitions(flutter_sequencer
    PRIVATE
    DART_SHARED_LIB
)
