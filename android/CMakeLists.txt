cmake_minimum_required(VERSION 3.18.1)

project(flutter_sequencer)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Define paths
set(ANDROID_DIR ${CMAKE_CURRENT_SOURCE_DIR})
set(IOS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../ios)
set(THIRD_PARTY_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party)

# Include directories
include_directories(
    ${ANDROID_DIR}/src/main/cpp
    ${IOS_DIR}/Classes
    ${THIRD_PARTY_DIR}/sfizz/include
    ${THIRD_PARTY_DIR}/sfizz_source/src
    ${THIRD_PARTY_DIR}/oboe/include
)

# Find system libraries
find_library(log-lib log)
find_library(android-lib android)

# Check for pre-built sfizz library
set(SFIZZ_LIBRARY ${THIRD_PARTY_DIR}/sfizz/lib/${ANDROID_ABI}/libsfizz.so)
if(EXISTS ${SFIZZ_LIBRARY})
    add_library(sfizz SHARED IMPORTED)
    set_target_properties(sfizz PROPERTIES
        IMPORTED_LOCATION ${SFIZZ_LIBRARY}
        INTERFACE_INCLUDE_DIRECTORIES "${THIRD_PARTY_DIR}/sfizz/include;${THIRD_PARTY_DIR}/sfizz_source/src"
    )
    set(SFIZZ_AVAILABLE TRUE)
    message(STATUS "Using pre-built sfizz library: ${SFIZZ_LIBRARY}")
else()
    set(SFIZZ_AVAILABLE FALSE)
    message(WARNING "sfizz library not found")
endif()

# Create main library
add_library(flutter_sequencer SHARED
    # Main plugin file
    ${ANDROID_DIR}/src/main/cpp/Plugin.cpp
    
    # Shared C++ classes from iOS
    ${IOS_DIR}/Classes/CallbackManager/CallbackManager.cpp
    ${IOS_DIR}/Classes/Scheduler/BaseScheduler.cpp
    ${IOS_DIR}/Classes/Scheduler/SchedulerEvent.cpp
    
    # Android-specific engine and instruments
    ${ANDROID_DIR}/src/main/cpp/AndroidEngine/AndroidEngine.cpp
    
    # Sfizz stub (always include for now since pre-built libraries are stubs)
    ${ANDROID_DIR}/src/main/cpp/sfizz_stub.cpp
)

# Set target properties
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
    ${THIRD_PARTY_DIR}/sfizz/include
    ${THIRD_PARTY_DIR}/sfizz_source/src
    ${ANDROID_DIR}/src/main/cpp/third_party/TinySoundFont
)

# Compile definitions
target_compile_definitions(flutter_sequencer PRIVATE
    ANDROID
    $<$<BOOL:${SFIZZ_AVAILABLE}>:SFIZZ_AVAILABLE=1>
    $<$<NOT:$<BOOL:${SFIZZ_AVAILABLE}>>:SFIZZ_AVAILABLE=0>
    $<$<CONFIG:Debug>:DEBUG>
    _GNU_SOURCE
    _FILE_OFFSET_BITS=64
)

# Add Oboe as subdirectory
add_subdirectory(${THIRD_PARTY_DIR}/oboe oboe-bin)

# Link libraries
target_link_libraries(flutter_sequencer
    ${log-lib}
    ${android-lib}
    oboe
)

# Link sfizz if available
if(SFIZZ_AVAILABLE)
    target_link_libraries(flutter_sequencer sfizz)
endif()

# Compiler options
target_compile_options(flutter_sequencer PRIVATE
    -Wall
    -Wextra
    -Wno-unused-parameter
    -fvisibility=hidden
    -fPIC
)