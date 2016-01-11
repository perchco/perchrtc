Pod::Spec.new do |s|

  s.name         = "nighthawk-webrtc"
  s.version      = "45"
  s.platform     = :ios, '7.0'
  s.summary      = "Pre-compiled library for libWebRTC."

  s.homepage     = "www.perch.co"
  s.author       = { "Chris Eagleston" => "chris@perch.co" }

  s.source       = { :http => "https://s3.amazonaws.com/perch-pods/webrtc-ios-chrome-m45-capture-xcode.zip" }

  s.source_files  = "include/talk/app/webrtc/*.h", "include/talk/app/webrtc/objc/**/*.h", "include/third_party/libyuv/include/**/*.h", "include/webrtc/video_frame.h", "include/webrtc/typedefs.h", "include/webrtc/common_types.h", "include/webrtc/base/*.h", "include/webrtc/common_video/**/*.h", "include/webrtc/modules/interface/*.h", "include/webrtc/modules/video_capture/**/*.h", "include/webrtc/p2p/base/*.h", "include/webrtc/system_wrappers/interface/*.h", "include/webrtc/system_wrappers/source/*.h", "include/talk/media/base/*.h", "include/talk/media/webrtc/*.h", "include/talk/session/media/*.h", "include/talk/p2p/base/*.h", "include/talk/xmllite/*.h", "include/talk/media/devices/*.h"
#  s.public_header_files = "include/third_party/libyuv/include/**/*.h"
  s.exclude_files = "include/talk/examples"

  s.requires_arc = true 
  s.frameworks   = 'QuartzCore', 'OpenGLES', 'GLKit', 'CoreAudio', 'CoreMedia', 'CoreVideo', 'AVFoundation', 'AudioToolbox', 'UIKit', 'Foundation', 'CoreGraphics', 'VideoToolbox'
  s.libraries = 'c', 'sqlite3', 'stdc++'
  s.vendored_libraries = "lib/libWebRTC-#{s.version}-1-arm-intel-Release.a"

  s.preserve_paths = 'include/talk/app/webrtc/objc/*', 'include/talk/app/webrtc/*', 'include/third_party/libyuv/include/*', "include/webrtc/video_frame.h", 'include/webrtc/typedefs.h', 'include/webrtc/common_types.h', 'include/webrtc/base/*', 'include/webrtc/common_video/*', 'include/webrtc/modules/interface/*', 'include/webrtc/modules/video_capture/*', 'include/webrtc/p2p/base/*.h', 'include/webrtc/system_wrappers/interface/*', 'include/webrtc/system_wrappers/source/*', 'include/talk/media/base/*', 'include/talk/media/webrtc/*', 'include/talk/session/media/*', 'include/talk/p2p/base/*', 'include/talk/xmllite/*', 'include/talk/media/devices/*', 'lib/*.a'

  s.xcconfig = {
                  'GCC_PREPROCESSOR_DEFINITIONS' => 'V8_DEPRECATION_WARNINGS EXPAT_RELATIVE_PATH FEATURE_ENABLE_VOICEMAIL JSONCPP_RELATIVE_PATH LOGGING=1 SRTP_RELATIVE_PATH FEATURE_ENABLE_SSL FEATURE_ENABLE_PSTN HAVE_SCTP HAVE_SRTP HAVE_WEBRTC_VIDEO HAVE_WEBRTC_VOICE DISABLE_NACL CHROMIUM_BUILD CR_CLANG_REVISION=239765-1 USE_LIBJPEG_TURBO=1 ENABLE_CONFIGURATION_POLICY SYSTEM_NATIVELY_SIGNALS_MEMORY_PRESSURE DONT_EMBED_BUILD_METADATA CLD_VERSION=2 DISABLE_FTP_SUPPORT=1 V8_USE_EXTERNAL_STARTUP_DATA IOS WEBRTC_MAC WEBRTC_IOS CARBON_DEPRECATED=YES HASH_NAMESPACE=__gnu_cxx WEBRTC_POSIX DISABLE_DYNAMIC_CAST _REENTRANT USE_LIBPCI=1 USE_OPENSSL=1 NDEBUG NVALGRIND DYNAMIC_ANNOTATIONS_ENABLED=0',
                  'OTHER_LDFLAGS' => '-ObjC',
#                  'HEADER_SEARCH_PATHS' => "${PODS_ROOT}/Headers/Private/nighthawk-webrtc/include/third_party/libyuv/include"
               }

  s.license      = {
    :type => 'http://www.webrtc.org/license-rights/license',
    :text => <<-LICENSE
      Copyright (c) 2011, The WebRTC project authors. All rights reserved.

      Redistribution and use in source and binary forms, with or without
      modification, are permitted provided that the following conditions are
      met:

        * Redistributions of source code must retain the above copyright
          notice, this list of conditions and the following disclaimer.

        * Redistributions in binary form must reproduce the above copyright
          notice, this list of conditions and the following disclaimer in
          the documentation and/or other materials provided with the
          distribution.

        * Neither the name of Google nor the names of its contributors may
          be used to endorse or promote products derived from this software
          without specific prior written permission.

      THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
      "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
      LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
      A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
      HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
      SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
      LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
      DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
      THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
      (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
      OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
      LICENSE
  }


end

