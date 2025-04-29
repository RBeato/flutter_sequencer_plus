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
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Mike Perri' => 'mikep@hey.com', 'Rodrigo Souza' => 'rbsou@hey.com' }
  s.source           = { :path => '.' }
  
  # Include ALL native files, including .hpp
  s.source_files     = 'Classes/**/*.{swift,h,m,mm,cpp,c,hpp}'
  s.public_header_files = 'Classes/**/*.h', 'Classes/**/*.hpp'
  s.module_map = 'Classes/module.modulemap'
  s.header_mappings_dir = 'Classes'
  
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'VALID_ARCHS' => 'arm64 arm64e x86_64',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'SWIFT_VERSION' => '5.0',
    'HEADER_SEARCH_PATHS' => '$(PODS_TARGET_SRCROOT)/../third_party/sfizz/src'
  }
  
  s.swift_version = '5.0'
  s.frameworks = 'Foundation', 'AVFoundation', 'AudioToolbox'

  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
end
