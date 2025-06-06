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
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.preserve_paths = 'third_party/sfizz/src/**/*'
  
  s.dependency 'Flutter'
  s.static_framework = true
  s.platform = :ios, '13.0'

  # Vendored frameworks
  s.vendored_frameworks = 'third_party/sfizz/xcframeworks/*.xcframework'
  
  # Pod target configuration
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'ENABLE_TESTABILITY' => 'YES',
    'STRIP_STYLE' => 'non-global',
    'HEADER_SEARCH_PATHS' => '$(inherited) $(PODS_TARGET_SRCROOT)/third_party/sfizz/src $(PODS_ROOT)/flutter_sequencer/third_party/sfizz/src',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++2a',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -std=c++2a -fmodules -fcxx-modules'
  }
  
  # User target configuration
  s.user_target_xcconfig = { 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64',
    'HEADER_SEARCH_PATHS' => '$(inherited) $(PODS_ROOT)/flutter_sequencer/third_party/sfizz/src'
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
