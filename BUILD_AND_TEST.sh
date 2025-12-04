#!/bin/bash

# Quick build and test script for VoiceInk with ML Kit Translation

echo "🚀 VoiceInk ML Kit Translation - Build & Test"
echo ""

# Check if we're in the right directory
if [ ! -f "VoiceInk-ios.xcworkspace/contents.xcworkspacedata" ]; then
    echo "❌ Error: Please run this script from the VoiceInk-iOS project root"
    exit 1
fi

echo "✅ Found workspace file"
echo ""

# Check if Pods are installed
if [ ! -d "Pods" ]; then
    echo "📦 Installing CocoaPods dependencies..."
    pod install
    echo ""
fi

echo "📱 Opening Xcode workspace..."
echo "   (Build in Xcode to avoid sandbox issues)"
echo ""

# Open in Xcode
open VoiceInk-ios.xcworkspace

echo "✅ Xcode should now be opening..."
echo ""
echo "📝 Next steps:"
echo "   1. Wait for Xcode to open"
echo "   2. Select your device/simulator"
echo "   3. Press Cmd+B to build"
echo "   4. Press Cmd+R to run"
echo "   5. Record a note in English"
echo "   6. Check console for translation logs"
echo "   7. Verify Spanish translation appears!"
echo ""
echo "📚 See TEST_TRANSLATION.md for detailed testing instructions"
echo ""


