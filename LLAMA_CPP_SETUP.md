# llama.cpp Integration Guide

This guide explains how to integrate llama.cpp for on-device translation in VoiceInk-iOS.

## Overview

The app now uses llama.cpp for local, offline translation from English to Spanish. This provides:
- **Privacy**: No data sent to external servers
- **Offline**: Works without internet connection
- **Free**: No API costs
- **Fast**: On-device inference

## Prerequisites

1. **Xcode 14.1+** (Swift 5.7+)
2. **iOS Deployment Target**: iOS 15.0+ (recommended: iOS 17.0+)
3. **Apple Silicon Mac** (for building the framework, or use pre-built)

## Step 1: Build llama.cpp XCFramework

### Option A: Build from Source (Recommended)

1. **Clone llama.cpp repository:**
   ```bash
   cd ~/Downloads
   git clone https://github.com/ggerganov/llama.cpp.git
   cd llama.cpp
   ```

2. **Build for iOS (Apple Silicon):**
   ```bash
   # Build XCFramework for iOS
   ./scripts/build-apple.sh
   ```
   
   This will create `llama.xcframework` in the build directory.

3. **Copy to project:**
   ```bash
   # Create a directory similar to whisper.xcframework location
   cp -r build-apple/llama.xcframework /Users/macbook/Dev/GitHub/VoiceInk-iOS/Downloads/build-apple/
   ```

### Option B: Use Pre-built Framework

If available, download a pre-built `llama.xcframework` and place it in:
```
/Users/macbook/Dev/GitHub/VoiceInk-iOS/Downloads/build-apple/llama.xcframework
```

## Step 2: Add Framework to Xcode Project

1. **Open Xcode project:**
   ```bash
   open VoiceInk-ios.xcodeproj
   ```

2. **Add llama.xcframework:**
   - In Xcode, go to your project target
   - Navigate to "Frameworks, Libraries, and Embedded Content"
   - Click "+" and select "Add Files..."
   - Navigate to `Downloads/build-apple/llama.xcframework`
   - Select it and click "Add"
   - Ensure "Embed & Sign" is selected

3. **Configure Bridging Header:**
   - In Xcode, select your project in the navigator
   - Select your target "VoiceInk-ios"
   - Go to "Build Settings"
   - Search for "Objective-C Bridging Header"
   - Set it to: `VoiceInk-ios/VoiceInk-ios-Bridging-Header.h`
   - This allows Swift to access the Objective-C++ bridge (`LlamaBridge`)

4. **Add Bridge Files to Target:**
   - Ensure `LlamaBridge.h` and `LlamaBridge.mm` are added to your target
   - Check "Target Membership" in the File Inspector for both files

5. **Update project.pbxproj** (if needed):
   The framework should be automatically added, but you may need to manually add references similar to how `whisper.xcframework` is configured.

## Step 3: Download Translation Model

You need a quantized GGUF model for translation. Recommended models:

### TinyLlama-1.1B-Chat (Q4_0) - ~700 MB
- **Best for**: Fast inference, older devices
- **URL**: https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_0.gguf

### Llama-3.2-1B-Instruct (Q4_0) - ~700 MB
- **Best for**: Better translation quality, still fast
- **URL**: https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_0.gguf

### Phi-2 (Q4_0) - ~1.5 GB
- **Best for**: Best quality, requires more memory
- **URL**: https://huggingface.co/microsoft/phi-2/resolve/main/phi-2.Q4_0.gguf

### Download Instructions:

1. **Download the model:**
   ```bash
   # Create translation models directory
   mkdir -p ~/Library/Developer/CoreSimulator/Devices/[DEVICE_ID]/data/Containers/Data/Application/[APP_ID]/Documents/TranslationModels
   
   # Download model (example)
   curl -L -o translation-model.gguf \
     https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_0.gguf
   ```

2. **Or use the app:**
   - The app will look for models in: `Documents/TranslationModels/`
   - Place your `.gguf` file there with name: `translation-model.gguf`
   - Or any `.gguf` file in that directory

## Step 4: Update LibLlama.swift

The `LibLlama.swift` file contains placeholder code that needs to be updated based on your llama.cpp API version. The actual API may vary, so you'll need to:

1. **Check llama.cpp C API:**
   - Review `llama.h` in the llama.cpp repository
   - Update function calls in `LibLlama.swift` to match

2. **Key functions to implement:**
   - `llama_load_model_from_file()` - Load GGUF model
   - `llama_new_context_with_model()` - Create inference context
   - `llama_tokenize()` - Convert text to tokens
   - `llama_decode()` - Run inference
   - `llama_token_to_piece()` - Convert tokens back to text
   - `llama_free()` - Cleanup

3. **Example structure:**
   ```swift
   // Load model
   var params = llama_model_default_params()
   let model = llama_load_model_from_file(path, params)
   
   // Create context
   var ctxParams = llama_context_default_params()
   ctxParams.n_ctx = 2048
   ctxParams.n_threads = 4
   let ctx = llama_new_context_with_model(model, ctxParams)
   ```

## Step 5: Test Translation

1. **Build and run the app**
2. **Record a note in English**
3. **Check console logs** for translation progress
4. **Verify Spanish translation** appears below English text

## Troubleshooting

### "Unable to import llama module"
- Ensure `llama.xcframework` is added to the project
- Check that it's linked in "Frameworks, Libraries, and Embedded Content"
- Verify the framework path is correct

### "No translation model available"
- Check that a `.gguf` file exists in `Documents/TranslationModels/`
- Verify the file is named `translation-model.gguf` or any `.gguf` file
- Check file permissions

### Model loading fails
- Verify the model file is not corrupted
- Check available device memory (models need 1-2GB free)
- Try a smaller quantized model (Q4_0 instead of Q8_0)

### Slow inference
- Use a smaller model (1B parameters instead of 7B)
- Reduce context size in `TranslationService.swift`
- Use fewer threads if device gets hot

## Performance Tips

1. **Use quantized models**: Q4_0 or Q5_0 provide good balance
2. **Limit context size**: 2048 tokens is sufficient for single sentences
3. **Optimize threads**: Use `cpuCount() - 1` for best performance
4. **Monitor memory**: Large models may cause memory pressure

## Next Steps

- [ ] Build llama.xcframework
- [ ] Add framework to Xcode project
- [ ] Download translation model
- [ ] Update LibLlama.swift with actual API calls
- [ ] Test translation functionality
- [ ] Add model download UI (optional)

## Resources

- [llama.cpp GitHub](https://github.com/ggerganov/llama.cpp)
- [GGUF Model Format](https://github.com/ggerganov/llama.cpp/blob/master/docs/GGUF.md)
- [iOS Build Guide](https://github.com/ggerganov/llama.cpp/tree/master/examples/llama.swift)
- [Hugging Face GGUF Models](https://huggingface.co/models?library=gguf)

