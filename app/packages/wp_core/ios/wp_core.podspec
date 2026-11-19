# Audio-Kern (core/) als Flutter-FFI-Plugin für iOS (ohne Aufnahme).
# Die Quellen liegen in core/src; Classes/ enthält nur Weiterleitungen per #include.
Pod::Spec.new do |s|
  s.name             = 'wp_core'
  s.version          = '0.0.1'
  s.summary          = 'Woodshed Player audio core'
  s.description      = 'Playback with tempo change without pitch change and loop.'
  s.homepage         = 'https://github.com/ingen63/Woodshed-Player'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Woodshed Player' => 'noreply@github.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '17.0'
  s.frameworks = 'AVFoundation', 'AudioToolbox', 'CoreAudio'
  # Absoluter Pfad: Flutter bindet das Plugin über einen Symlink ein, relative Suchpfade zeigen sonst ins Leere.
  core = File.expand_path('../../../../core', File.realpath(__dir__))
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    # #9/AK7: no fused multiply-add, same samples as the web core and the tests (core/CMakeLists.txt)
    'OTHER_CFLAGS' => '$(inherited) -ffp-contract=off',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -ffp-contract=off',
    'HEADER_SEARCH_PATHS' => [
      "\"#{core}/include\"", "\"#{core}/src\"", "\"#{core}/third_party/miniaudio\"",
      "\"#{core}/third_party/signalsmith-stretch/include\"", "\"#{core}/third_party/signalsmith-linear/include\""
    ].join(' '),
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
end
