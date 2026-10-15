#!/bin/sh
# Compile the plain Objective-C++ tracer. No Theos, Logos, Homebrew, or Substrate.
set -eu
cd "$(dirname "$0")"
command -v xcrun >/dev/null 2>&1 || {
    echo 'Requires macOS with Xcode and the iPhoneOS SDK (xcrun unavailable).' >&2
    exit 1
}
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
mkdir -p build
xcrun --sdk iphoneos clang++ -x objective-c++ -std=c++17 -fobjc-arc -fblocks \
    -arch arm64 -isysroot "$SDK" -miphoneos-version-min=15.0 \
    -Wall -Wextra -Werror -Wno-unused-parameter -dynamiclib \
    -framework Foundation -framework UIKit \
    -install_name @rpath/TempMailTrace.dylib \
    TempMailTrace.mm -o build/TempMailTrace.dylib
codesign --force --sign - --timestamp=none build/TempMailTrace.dylib
file build/TempMailTrace.dylib
codesign --verify --verbose=2 build/TempMailTrace.dylib
