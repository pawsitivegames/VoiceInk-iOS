#!/bin/bash

# Build script for llama.cpp XCFramework for iOS
# This script builds llama.cpp and creates an XCFramework

set -e

echo "🚀 Building llama.cpp for iOS..."

# Check if we're in the right directory
if [ ! -f "VoiceInk-ios.xcodeproj/project.pbxproj" ]; then
    echo "❌ Error: Please run this script from the VoiceInk-iOS project root"
    exit 1
fi

# Create downloads directory if it doesn't exist
DOWNLOADS_DIR="$HOME/Downloads"
BUILD_DIR="$DOWNLOADS_DIR/llama.cpp-build"
LLAMA_REPO="$DOWNLOADS_DIR/llama.cpp"
FRAMEWORK_OUTPUT="$DOWNLOADS_DIR/build-apple"

echo "📦 Setting up directories..."
mkdir -p "$BUILD_DIR"
mkdir -p "$FRAMEWORK_OUTPUT"

# Clone llama.cpp if it doesn't exist
if [ ! -d "$LLAMA_REPO" ]; then
    echo "📥 Cloning llama.cpp repository..."
    cd "$DOWNLOADS_DIR"
    git clone https://github.com/ggerganov/llama.cpp.git
    cd llama.cpp
else
    echo "✅ llama.cpp repository already exists, updating..."
    cd "$LLAMA_REPO"
    git pull
fi

echo "🔨 Building for iOS (arm64 device)..."
cd "$LLAMA_REPO"

# Check if build script exists
if [ -f "./scripts/build-apple.sh" ]; then
    echo "📱 Using build-apple.sh script..."
    ./scripts/build-apple.sh
    
    # Check if framework was created
    if [ -d "build-apple/llama.xcframework" ]; then
        echo "✅ Framework built successfully!"
        cp -r "build-apple/llama.xcframework" "$FRAMEWORK_OUTPUT/"
        echo "✅ Framework copied to $FRAMEWORK_OUTPUT/llama.xcframework"
        echo ""
        echo "🎉 Next steps:"
        echo "1. Open VoiceInk-ios.xcodeproj in Xcode"
        echo "2. Drag $FRAMEWORK_OUTPUT/llama.xcframework into the project"
        echo "3. Ensure 'Embed & Sign' is selected"
        echo "4. Build and run!"
        exit 0
    fi
fi

# Manual build if script doesn't work
echo "🔧 Attempting manual build..."

# Build for iOS device (arm64)
mkdir -p build-ios-device
cd build-ios-device

cmake .. \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
    -DLLAMA_METAL=ON \
    -DCMAKE_BUILD_TYPE=Release

make -j$(sysctl -n hw.ncpu)

cd ..

# Build for iOS simulator (arm64 for Apple Silicon Macs)
mkdir -p build-ios-simulator
cd build-ios-simulator

cmake .. \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_SYSROOT=$(xcrun --sdk iphonesimulator --show-sdk-path) \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
    -DLLAMA_METAL=OFF \
    -DCMAKE_BUILD_TYPE=Release

make -j$(sysctl -n hw.ncpu)

cd ..

# Create XCFramework
echo "📦 Creating XCFramework..."

xcodebuild -create-xcframework \
    -library build-ios-device/libllama.a \
    -headers include \
    -library build-ios-simulator/libllama.a \
    -headers include \
    -output "$FRAMEWORK_OUTPUT/llama.xcframework"

if [ -d "$FRAMEWORK_OUTPUT/llama.xcframework" ]; then
    echo "✅ XCFramework created successfully at $FRAMEWORK_OUTPUT/llama.xcframework"
    echo ""
    echo "🎉 Next steps:"
    echo "1. Open VoiceInk-ios.xcodeproj in Xcode"
    echo "2. Drag $FRAMEWORK_OUTPUT/llama.xcframework into the project"
    echo "3. Ensure 'Embed & Sign' is selected"
    echo "4. Build and run!"
else
    echo "❌ Failed to create XCFramework"
    echo "💡 You may need to manually build llama.cpp"
    echo "   See LLAMA_CPP_SETUP.md for detailed instructions"
    exit 1
fi


