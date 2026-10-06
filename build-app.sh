#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Butterfly"
APP_BUNDLE="${SCRIPT_DIR}/${APP_NAME}.app"
BUILD_DIR="${SCRIPT_DIR}/.build/debug"

echo "Building ${APP_NAME}..."
swift build -c release

# Use release build if available, otherwise debug
if [ -f "${SCRIPT_DIR}/.build/release/${APP_NAME}" ]; then
    EXECUTABLE="${SCRIPT_DIR}/.build/release/${APP_NAME}"
else
    EXECUTABLE="${BUILD_DIR}/${APP_NAME}"
fi

echo "Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy executable
cp "${EXECUTABLE}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Create Info.plist
cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.butterfly.keyboard</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2024</string>
</dict>
</plist>
EOF

echo "App bundle created at: ${APP_BUNDLE}"
echo ""
echo "To run: open ${APP_BUNDLE}"
echo "Or: ${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"



