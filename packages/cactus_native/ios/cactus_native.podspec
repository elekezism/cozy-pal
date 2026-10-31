# Links the prebuilt Cactus engine (cactus-ios.xcframework) into the app.
# Put the xcframework next to this file with tool/setup_platforms.dart
# (or the GitHub workflow). Without it the app still builds and simply
# runs without on-device AI.
Pod::Spec.new do |s|
  s.name             = 'cactus_native'
  s.version          = '0.0.1'
  s.summary          = 'Prebuilt Cactus engine for Cozy Pal.'
  s.homepage         = 'https://github.com/cactus-compute/cactus'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Cozy Pal' => 'dev@cozypal.app' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '16.4'

  if File.exist?(File.join(__dir__, 'cactus-ios.xcframework'))
    s.vendored_frameworks = 'cactus-ios.xcframework'
    s.frameworks = 'Accelerate', 'CoreML', 'Foundation', 'Metal',
                   'MetalPerformanceShaders', 'Security', 'SystemConfiguration', 'CFNetwork'
  end

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
