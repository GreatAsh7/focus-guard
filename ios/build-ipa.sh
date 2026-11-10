#!/bin/sh
# Builds an unsigned FocusGuard.ipa for SideStore / AltStore to sign and install.
# Run on a Mac with Xcode and XcodeGen:  brew install xcodegen && ./build-ipa.sh
set -e
cd "$(dirname "$0")"

xcodegen generate
xcodebuild -project FocusGuard.xcodeproj -scheme FocusGuard -configuration Release \
  -sdk iphoneos -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" | tail -n 5

rm -rf build/ipa && mkdir -p build/ipa/Payload
cp -R build/Build/Products/Release-iphoneos/FocusGuard.app build/ipa/Payload/
(cd build/ipa && zip -qr ../../FocusGuard.ipa Payload)
echo "Built $(pwd)/FocusGuard.ipa"
