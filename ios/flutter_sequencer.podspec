#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_sequencer.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_sequencer'
  s.version          = '0.0.2'
  s.summary          = 'A new flutter plugin project.'
  s.description      = <<-DESC
A new flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  
  # Remove resource bundles for prepare.sh
  # s.resource_bundles = {
  #   'flutter_sequencer' => ['prepare.sh']
  # }
  
  s.xcconfig = {
    'USER_HEADER_SEARCH_PATHS' => '"${PROJECT_DIR}/.."/Classes/CallbackManager/*,"${PROJECT_DIR}/.."/Classes/Scheduler/*,"${PROJECT_DIR}/.."/Classes/AudioUnit/Sfizz/SfizzDSPKernelAdapter.h',
  }
  s.dependency 'Flutter'
  s.static_framework = true
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'ENABLE_TESTABILITY' => 'YES',
    'STRIP_STYLE' => 'non-global',
    'HEADER_SEARCH_PATHS' => '$(PODS_TARGET_SRCROOT)/third_party/sfizz/include $(PODS_TARGET_SRCROOT)/third_party/TSF',
    'VALID_ARCHS' => 'arm64 x86_64'
  }
  s.user_target_xcconfig = { 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'
  s.library = 'c++'
  s.xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++2a',
    'CLANG_CXX_LIBRARY' => 'libc++'
  }
  
  # Create sfizz mock directory and files before pod install
  s.prepare_command = <<-CMD
    mkdir -p third_party/TSF
    mkdir -p third_party/sfizz/include
    
    curl -L https://github.com/schellingb/TinySoundFont/raw/master/tsf.h > third_party/TSF/tsf.h
    curl -L https://github.com/schellingb/TinySoundFont/raw/master/tml.h > third_party/TSF/tml.h
    curl -L https://github.com/schellingb/TinySoundFont/raw/master/tfs.h > third_party/TSF/tfs.h
    
    cat > third_party/sfizz/include/sfizz.hpp << 'EOF'
#pragma once
#include <string>
namespace sfz {
    class Sfizz {
    public:
        Sfizz() {}
        ~Sfizz() {}
        void setSamplesPerBlock(int samplesPerBlock) {}
        void setSampleRate(float sampleRate) {}
        bool loadSfzFile(const std::string& path) { return true; }
        bool loadSfzString(const std::string& sfz) { return true; }
        bool loadScalaFile(const std::string& path) { return true; }
        bool loadScalaString(const std::string& scala) { return true; }
        void renderBlock(float* outputLeft, float* outputRight, int numFrames) {}
        void noteOn(int channel, int note, int velocity) {}
        void noteOff(int channel, int note, int velocity) {}
        void cc(int channel, int cc, int value) {}
        void pitchWheel(int channel, int value) {}
    };
}
EOF
    
    echo "Mock setup complete"
  CMD
  
  # Remove vendored libraries since we're mocking them
  # s.vendored_libraries = 'third_party/sfizz/build/libsfizz_fat.a'
end
