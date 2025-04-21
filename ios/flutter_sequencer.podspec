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
  s.public_header_files = 'Classes/*.h'
  s.header_mappings_dir = 'Classes'
  s.resource_bundles = {
    'flutter_sequencer' => ['prepare.sh']
  }
  # TODO: Verify module.modulemap and C API bridge (EngineBindings.h/cpp) exposure for Swift/ObjC interop
  s.xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++2a',
    'CLANG_CXX_LIBRARY' => 'libc++'
  }
  s.dependency 'Flutter'
  s.static_framework = true
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64,i386',
    'ENABLE_TESTABILITY' => 'YES',
    'STRIP_STYLE' => 'non-global'
  }
  s.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }
  s.swift_version = '5.0'
  s.library = 'c++'
  s.prepare_command = './prepare.sh'
  s.vendored_libraries = 'third_party/sfizz/build/libsfizz_fat.a'
  s.module_map = 'Classes/module.modulemap'
  s.frameworks = 'AudioUnit', 'AVFoundation', 'CoreAudio'
  # After editing, validate with: pod lib lint flutter_sequencer.podspec
end
