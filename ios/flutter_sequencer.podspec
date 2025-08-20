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
  s.source_files = 'Classes/**/*.{h,m,mm,swift,cpp,hpp}'
  s.public_header_files = 'Classes/**/*.h'
  s.preserve_paths = 'third_party/sfizz/src/**/*'
  
  # Ensure specific headers are public
  s.private_header_files = []
  
  s.dependency 'Flutter'
  s.static_framework = true
  s.platform = :ios, '13.0'

  # Vendored frameworks
  s.vendored_frameworks = 'third_party/sfizz/xcframeworks/*.xcframework'
  
  # Pod target configuration - Production optimized while preserving FFI symbols
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'NO',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'ENABLE_TESTABILITY' => 'YES',
    'STRIP_STYLE' => 'non-global',
    'HEADER_SEARCH_PATHS' => '$(inherited) $(PODS_TARGET_SRCROOT)/third_party/sfizz/src $(PODS_ROOT)/flutter_sequencer/third_party/sfizz/src $(PODS_TARGET_SRCROOT)/Classes $(PODS_TARGET_SRCROOT)/Classes/AudioUnit/Sfizz',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -std=c++17',
    'CLANG_ENABLE_MODULES' => 'NO',
    'SWIFT_VERSION' => '5.0',
    'SWIFT_COMPILATION_MODE' => 'wholemodule',
    'SWIFT_OPTIMIZATION_LEVEL' => '-O',
    'SWIFT_ENABLE_LIBRARY_EVOLUTION' => 'NO',
    'OTHER_LDFLAGS' => '$(inherited) -Wl,-exported_symbol,_setup_engine -Wl,-exported_symbol,_destroy_engine -Wl,-exported_symbol,_remove_track -Wl,-exported_symbol,_reset_track -Wl,-exported_symbol,_get_position -Wl,-exported_symbol,_engine_play -Wl,-exported_symbol,_engine_pause -Wl,-exported_symbol,_engine_stop -Wl,-exported_symbol,_add_track_sf2 -Wl,-exported_symbol,_add_track_sfz -Wl,-exported_symbol,_get_track_volume -Wl,-exported_symbol,_handle_events_now -Wl,-exported_symbol,_schedule_events -Wl,-exported_symbol,_clear_events'
  }
  
  # User target configuration - Production optimized
  s.user_target_xcconfig = { 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64',
    'HEADER_SEARCH_PATHS' => '$(inherited) $(PODS_ROOT)/flutter_sequencer/third_party/sfizz/src',
    'ENABLE_BITCODE' => 'NO',
    'VALID_ARCHS' => 'arm64 x86_64',
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'NO',
    'OTHER_LDFLAGS' => '$(inherited) -framework AudioToolbox -framework AVFoundation -framework CoreAudio',
    'CLANG_ENABLE_MODULES' => 'NO',
    'SWIFT_ENABLE_LIBRARY_EVOLUTION' => 'NO',
    'SWIFT_COMPILATION_MODE' => 'wholemodule'
  }
  
  s.swift_version = '5.0'
  s.library = 'c++'
  
  # Don't run prepare command when used as dependency
  if Dir.exist?('third_party/sfizz/xcframeworks') && Dir.exist?('third_party/sfizz/src')
    puts "sfizz dependencies already present, skipping prepare.sh"
  else
    s.prepare_command = './prepare.sh'
  end
end
