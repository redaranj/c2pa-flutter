Pod::Spec.new do |s|
  s.name             = 'c2pa_flutter'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin for C2PA (Coalition for Content Provenance and Authenticity)'
  s.description      = <<-DESC
A Flutter plugin that provides C2PA functionality for verifying content authenticity and provenance.
                       DESC
  s.homepage         = 'https://github.com/nicktardif/c2pa-flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Guardian Project' => 'support@guardianproject.info' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.9'
  
  s.preserve_paths = ['C2PAC.xcframework']
  s.vendored_frameworks = 'C2PAC.xcframework'
end
