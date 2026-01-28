# Stub podspec for Flutter plugin validation on non-macOS platforms.
# iOS builds use Swift Package Manager (see ios/c2pa_flutter/Package.swift).
# This file exists only to satisfy Flutter's plugin validation on Linux CI.

Pod::Spec.new do |s|
  s.name             = 'c2pa_flutter'
  s.version          = '0.0.1'
  s.summary          = 'C2PA Flutter plugin - iOS uses Swift Package Manager'
  s.description      = <<-DESC
Flutter plugin for C2PA content authenticity. iOS builds require Swift Package Manager.
This podspec is a stub for CI validation only.
                       DESC
  s.homepage         = 'https://github.com/user/c2pa_flutter'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Guardian Project' => 'support@guardianproject.info' }
  s.source           = { :path => '.' }
  s.source_files     = 'c2pa_flutter/Sources/c2pa_flutter/**/*.swift'
  s.platform         = :ios, '16.0'
  s.swift_version    = '5.9'
  s.dependency 'Flutter'

  # This is a stub - actual iOS builds use Swift Package Manager
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
