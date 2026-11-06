#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodegen generate
xcodebuild -project UsageWidget.xcodeproj -scheme UsageWidget -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
app_path="$PWD/build/Build/Products/Release/Usage Widget.app"
codesign --force --sign - --entitlements Widget/UsageWidget.entitlements "$app_path/Contents/PlugIns/UsageWidgetExtension.appex"
codesign --force --sign - --entitlements App/UsageWidget.entitlements "$app_path"
codesign --verify --deep --strict "$app_path"
print "Built: $app_path"
