#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_sequencer.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_sequencer'
  s.version          = '0.1.0'
  s.summary          = 'A Flutter plugin for audio sequencing and synthesis'
  s.description      = 'A Flutter plugin that provides audio sequencing and synthesis capabilities using native platform implementations.'
  s.homepage         = 'https://github.com/rbsou/flutter_sequencer_plus'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Mike Perri' => 'mikep@hey.com', 'Rodrigo Souza' => 'rbsou@hey.com' }
  s.source           = { :path => '.' }
  
  # Platform setup
  s.platform = :osx, '10.13'
  s.osx.deployment_target = '10.13'
  
  # Source files
  s.source_files = 'Classes/**/*.{h,m,mm,swift}'
  s.public_header_files = 'Classes/**/*.h'
  s.private_header_files = 'Classes/**/*.h'
  
  # Module map
  s.module_map = 'Classes/module.modulemap'
  
  # Compiler flags
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_VERSION' => '5.0',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS' => '$(OTHER_CFLAGS) -fno-objc-arc -fmodules -fcxx-modules',
    'OTHER_CFLAGS' => '-fno-objc-arc -fmodules -fcxx-modules',
    'HEADER_SEARCH_PATHS' => '${PODS_ROOT}/Headers/Public',
    'LIBRARY_SEARCH_PATHS' => '${PODS_CONFIGURATION_BUILD_DIR}',
    'SWIFT_INCLUDE_PATHS' => '${PODS_TARGET_SRCROOT}/Classes/**',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) GPB_USE_PROTOBUF_FRAMEWORK_IMPORTS=1',
    'ENABLE_BITCODE' => 'NO',
    'STRIP_STYLE' => 'non-global',
    'APPLICATION_EXTENSION_API_ONLY' => 'NO'
  }
  
  # Dependencies
  s.frameworks = 'Foundation', 'CoreAudioKit', 'AudioToolbox', 'AVFoundation', 'CoreAudio', 'CoreMIDI', 'AudioUnit'
  s.libraries = 'c++'
  s.requires_arc = true
  
  # Resource bundles
  s.resource_bundles = {
    'flutter_sequencer' => ['prepare.sh']
  }
  s.xcconfig = {
    'USER_HEADER_SEARCH_PATHS' => '"${PROJECT_DIR}/.."/Classes/CallbackManager/*,"${PROJECT_DIR}/.."/Classes/Scheduler/*,"${PROJECT_DIR}/.."/Classes/AudioUnit/Sfizz/SfizzDSPKernelAdapter.h',
  }
  s.dependency 'FlutterMacOS'
  s.static_framework = true
  s.platform = :osx, '10.14'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=macosx*]' => 'i386',
    'ENABLE_TESTABILITY' => 'YES',
    'STRIP_STYLE' => 'non-global',
    'HEADER_SEARCH_PATHS' => '$(PODS_TARGET_SRCROOT)/third_party/sfizz/src',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++2a',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS' => '-std=c++2a -fmodules -fcxx-modules -fno-objc-arc',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) SFIZZ_AUDIOUNIT=1',
    'OTHER_SWIFT_FLAGS' => '$(inherited) -DSFIZZ_AUDIOUNIT'
  }
  
  s.swift_version = '5.0'
  s.library = 'c++'
  s.xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++2a',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'CONFIGURATION_BUILD_DIR' => '${PODS_CONFIGURATION_BUILD_DIR}/flutter_sequencer',
    'OTHER_CFLAGS' => '$(inherited) -include ${PODS_ROOT}/../overrides.xcconfig'
  }
  s.prepare_command = './prepare.sh'
  s.vendored_frameworks = Dir['third_party/sfizz/xcframeworks/*.xcframework']
end
