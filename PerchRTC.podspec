Pod::Spec.new do |s|

  s.name         = 'PerchRTC'
  s.version      = '0.1'
  s.license      = 'MIT'
  s.summary      = 'Chrome powered WebRTC framework for iOS.'
  s.homepage     = 'https://github.com/perchco/perchrtc'

  s.homepage     = "www.perch.co"
  s.authors      = { 'Chris Eagleston' => 'chris@perch.co', 'Sam Symons' => 'sam@samsymons.com'}
  s.requires_arc = true 

  s.platform     = :ios, '8.1'

  s.frameworks   = 'QuartzCore', 'OpenGLES', 'GLKit', 'CoreAudio', 'CoreMedia', 'CoreVideo', 'AVFoundation', 'AudioToolbox', 'UIKit', 'Foundation', 'CoreGraphics', 'VideoToolbox'
  s.libraries = 'c', 'sqlite3', 'stdc++'

  s.source_files = 'PerchRTC/PerchRTC.h'
  s.source_files = 'PerchRTC/{Audio,Capture,Logging,Media,Renderers}/*.{h,m}'
  s.public_header_files = 'PerchRTC/PerchRTC.h'

  s.prefix_header_contents = '
                              #import <CocoaLumberjack/DDLog.h>
                              #ifdef DEBUG
                              static const int ddLogLevel = LOG_LEVEL_VERBOSE;
                              #else
                              static const int ddLogLevel = LOG_LEVEL_WARN;
                              #endif
                              '
  
  s.dependency 'nighthawk-webrtc'
  s.dependency 'CocoaLumberjack', '~> 1.0'

  s.subspec 'CaptureKit' do |ss|
    ss.source_files = 'PerchRTC/CaptureKit/*.{h,mm}'

    # We subclass C++ WebRTC, which does not support RTTI.
    s.xcconfig = {
                  'OTHER_CPPFLAGS' => '-fno-rtti'
                 }
  end

end