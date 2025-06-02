cmake_minimum_required(VERSION 3.10.2)

# Set up the project
project(flutter_sequencer_plus)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DSFIZZ_SHARED=1 -DSFIZZ_STATIC=0 -DANDROID")

# Set output directories
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/../jniLibs/${ANDROID_ABI})

# Set paths
set(THIRD_PARTY_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party)
set(SFIZZ_DIR ${THIRD_PARTY_DIR}/sfizz)
set(SFIZZ_INCLUDE_DIR ${SFIZZ_DIR}/include/sfizz)
set(SFIZZ_LIBRARY ${SFIZZ_DIR}/lib/${ANDROID_ABI}/libsfizz.so)

# Include directories
include_directories(
    src/main/cpp
    ${SFIZZ_DIR}/include
)

# Find required packages
find_package(oboe REQUIRED CONFIG)
find_package(OpenSLES REQUIRED)

# Check for real sfizz library and headers for the current ABI
if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/sfizz/lib/${ANDROID_ABI}/libsfizz.so")
    message(FATAL_ERROR "[CMakeLists.txt] ERROR: sfizz library not found for ABI: ${ANDROID_ABI}. Please provide third_party/sfizz/lib/${ANDROID_ABI}/libsfizz.so.")
endif()
if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/sfizz/include/sfizz/sfizz.h")
    message(FATAL_ERROR "[CMakeLists.txt] ERROR: sfizz.h not found. Please provide third_party/sfizz/include/sfizz/sfizz.h.")
endif()

            "typedef struct sfizz_import_t { const unsigned char* data; unsigned long size; } sfizz_import_t;\n\n"
            "// Dummy function declarations\n"
            "sfizz_synth_t* sfizz_create_synth();\n"
            "void sfizz_free(sfizz_synth_t* synth);\n"
            "int sfizz_load_file(sfizz_synth_t* synth, const char* path);\n"
            "int sfizz_load_memory(sfizz_synth_t* synth, const char* path, const unsigned char* data, unsigned long size);\n"
            "int sfizz_set_samples_per_block(sfizz_synth_t* synth, int samples_per_block);\n"
            "int sfizz_set_sample_rate(sfizz_synth_t* synth, float sample_rate);\n"
            "void sfizz_send_note_on(sfizz_synth_t* synth, int delay, int note_number, int velocity);\n"
            "void sfizz_send_note_off(sfizz_synth_t* synth, int delay, int note_number, int velocity);\n"
            "void sfizz_render_block(sfizz_synth_t* synth, float** buffers, int num_frames);\n\n"
            "#ifdef __cplusplus\n"
            "}\n"
            "#endif\n\n"
            "#endif // SFIZZ_H\n"
        )
    endif()
endif()

# Add sfizz as an imported library
add_library(sfizz SHARED IMPORTED)
set_target_properties(sfizz PROPERTIES
    IMPORTED_LOCATION ${SFIZZ_LIBRARY}
    INTERFACE_INCLUDE_DIRECTORIES "${SFIZZ_DIR}/include"
)

# Add the native library with core source files
add_library(flutter_sequencer SHARED
    src/main/cpp/flutter_sequencer.cpp
    src/main/cpp/audio_player.cpp
    src/main/cpp/audio_player_manager.cpp
    src/main/cpp/audio_source.cpp
    src/main/cpp/audio_source_asset.cpp
    src/main/cpp/audio_source_file.cpp
    src/main/cpp/audio_source_memory.cpp
    src/main/cpp/audio_source_sf2.cpp
    src/main/cpp/audio_source_sfz.cpp
    src/main/cpp/audio_source_oscillator.cpp
    src/main/cpp/audio_source_noise.cpp
    src/main/cpp/audio_source_silence.cpp
    src/main/cpp/audio_stream.cpp
    src/main/cpp/audio_utils.cpp
)

# Include directories for the native library
target_include_directories(flutter_sequencer PRIVATE
    src/main/cpp
    third_party/tinysoundfont/src
    third_party/sfizz/include
)

# Add compiler definitions
target_compile_definitions(flutter_sequencer PRIVATE
    -DSFIZZ_SHARED=1
    -DSFIZZ_STATIC=0
    $<$<CONFIG:Debug>:-DDEBUG>
)

# Set C++ standard and properties
target_compile_features(flutter_sequencer PRIVATE cxx_std_17)
set_target_properties(flutter_sequencer PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
    POSITION_INDEPENDENT_CODE ON
)

# Link libraries
target_link_libraries(flutter_sequencer
    sfizz
    oboe::oboe
    OpenSLES
    log
    android
)

# Set install path for the library
set_target_properties(flutter_sequencer PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}
)

# Add TinySoundFont
set(TSF_DIR ${THIRD_PARTY_DIR}/TinySoundFont)
set(TSF_SOURCES ${TSF_DIR}/tsf.cpp)

# Create a static library for TinySoundFont
add_library(tsf STATIC ${TSF_SOURCES})
target_include_directories(tsf PUBLIC ${TSF_DIR})

# Set C++ standard for TinySoundFont
target_compile_features(tsf PRIVATE cxx_std_11)

# Disable warnings for TinySoundFont
if(MSVC)
    target_compile_options(tsf PRIVATE /W0)
else()
    target_compile_options(tsf PRIVATE -w)
endif()

# Add Oboe as a subdirectory (this creates the oboe target)
set(OBOE_DIR ${THIRD_PARTY_DIR}/oboe)
add_subdirectory(${OBOE_DIR} ${CMAKE_CURRENT_BINARY_DIR}/oboe)
target_include_directories(oboe PUBLIC ${OBOE_DIR}/include)

# Add required compiler definitions
add_definitions(-DSFIZZ_SHARED=1 -DSFIZZ_STATIC=0)

# Find and link required system libraries
find_library(log-lib log)
find_library(android-lib android)
find_library(OpenSLES-lib OpenSLES)
find_library(EGL-lib EGL)
find_library(GLESv2-lib GLESv2)



ADD_LIBRARY(flutter_sequencer SHARED)
TARGET_INCLUDE_DIRECTORIES(flutter_sequencer PRIVATE
        ../ios/Classes/CallbackManager
        ../ios/Classes/Scheduler
        ../ios/Classes/IInstrument
        )
TARGET_SOURCES(flutter_sequencer PRIVATE
        ../ios/Classes/CallbackManager/CallbackManager.h
        ../ios/Classes/CallbackManager/CallbackManager.cpp
        ../ios/Classes/Scheduler/BaseScheduler.h
        ../ios/Classes/Scheduler/BaseScheduler.cpp
        ../ios/Classes/Scheduler/Buffer.h
        ../ios/Classes/Scheduler/SchedulerEvent.h
        ../ios/Classes/Scheduler/SchedulerEvent.cpp
        ./src/main/cpp/AndroidEngine/AndroidEngine.h
        ./src/main/cpp/AndroidEngine/AndroidEngine.cpp
        ../ios/Classes/IInstrument/IInstrument.h
        ../ios/Classes/IInstrument/SharedInstruments/SfizzSamplerInstrument.h
        ./src/main/cpp/AndroidInstruments/Mixer.h
        ./src/main/cpp/AndroidInstruments/SoundFontInstrument.h
        ./src/main/cpp/Utils/AssetManager.h
        ./src/main/cpp/Utils/Logging.h
        ./src/main/cpp/Utils/OptionArray.h
        ./src/main/cpp/Plugin.cpp
        )

# Link all libraries to the main target
target_link_libraries(flutter_sequencer
    PRIVATE
        oboe
        tsf
        sfizz
        ${log-lib}
        ${android-lib}
        ${OpenSLES-lib}
        ${EGL-lib}
        ${GLESv2-lib}
        atomic
        c++_shared
)

# Add linker flags
target_link_options(flutter_sequencer
    PRIVATE
        -Wl,--no-undefined
        -Wl,--gc-sections
        -Wl,-z,nocopyreloc
)

# Set compile definitions
target_compile_definitions(flutter_sequencer
    PRIVATE
        $<$<CONFIG:Debug>:DEBUG=1>
)

# Set include directories
target_include_directories(flutter_sequencer
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src/main/cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/../ios/Classes
)

# Set compile options
target_compile_options(flutter_sequencer
    PRIVATE
        -fexceptions
        -frtti
        -fno-limit-debug-info
        -fno-rtti
        -fno-exceptions
        -fno-unwind-tables
        -fno-stack-protector
        -fno-strict-aliasing
        -fPIC
        -fPIE
        -fvisibility=hidden
        -Wall
        -Wextra
        -Werror
        -Wno-unused-parameter
        -Wno-unused-variable
        -Wno-unused-function
        -Wno-missing-field-initializers
        -Wno-sign-compare
        -Wno-unused-but-set-variable
        -Wno-unused-result
        -Wno-format
        -Wno-format-security
        -Wno-deprecated-declarations
)
