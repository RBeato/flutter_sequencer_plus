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
  s.platform = :osx, '10.14'
  s.osx.deployment_target = '10.14'
  
  # Source files
  s.source_files = 'Classes/**/*.{h,m,mm,swift}'
  s.public_header_files = 'Classes/**/*.h'
  s.preserve_paths = 'third_party/sfizz/src/**/*'
  
  # Disable module map to avoid conflicts
  s.module_map = false
  
  # Dependencies
  s.dependency 'FlutterMacOS'
  s.static_framework = true
  
  # Vendored frameworks
  s.vendored_frameworks = 'third_party/sfizz/xcframeworks/*.xcframework'
  
  # Frameworks
  s.frameworks = 'Foundation', 'CoreAudioKit', 'AudioToolbox', 'AVFoundation', 'CoreAudio', 'CoreMIDI', 'AudioUnit'
  s.libraries = 'c++'
  s.requires_arc = true
  
  # Pod target configuration
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'NO',
    'EXCLUDED_ARCHS[sdk=macosx*]' => 'i386',
    'ENABLE_TESTABILITY' => 'YES',
    'STRIP_STYLE' => 'non-global',
    'HEADER_SEARCH_PATHS' => '$(inherited) $(PODS_TARGET_SRCROOT)/Classes $(PODS_TARGET_SRCROOT)/third_party/sfizz/src $(PODS_ROOT)/flutter_sequencer/third_party/sfizz/src',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++2a',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -std=c++2a -fmodules -fcxx-modules',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) SFIZZ_AUDIOUNIT=1',
    'OTHER_SWIFT_FLAGS' => '$(inherited) -DSFIZZ_AUDIOUNIT -import-objc-header $(PODS_TARGET_SRCROOT)/Classes/FlutterSequencer-Bridging-Header.h',
    'SWIFT_OBJC_BRIDGING_HEADER' => '$(PODS_TARGET_SRCROOT)/Classes/FlutterSequencer-Bridging-Header.h',
    'ENABLE_BITCODE' => 'NO',
    'APPLICATION_EXTENSION_API_ONLY' => 'NO'
  }
  
  # User target configuration
  s.user_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '$(inherited) $(PODS_ROOT)/flutter_sequencer/Classes $(PODS_ROOT)/flutter_sequencer/third_party/sfizz/src'
  }
  
  s.swift_version = '5.0'
  
  # Don't run prepare command when used as dependency
  if Dir.exist?('third_party/sfizz/xcframeworks') && Dir.exist?('third_party/sfizz/src')
    puts "sfizz dependencies already present, skipping prepare.sh"
  else
    s.prepare_command = './prepare.sh'
  end
end
