//
//  LlamaBridge.h
//  VoiceInk-ios
//
//  Objective-C++ bridge for llama.cpp
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LlamaBridge : NSObject

/// Initialize llama.cpp with a model
/// - Parameters:
///   - modelPath: Path to the GGUF model file
///   - contextSize: Context window size (e.g., 2048)
///   - maxTokens: Maximum tokens to generate (e.g., 256)
- (instancetype)initWithModelPath:(NSString *)modelPath 
                          context:(int)contextSize 
                           tokens:(int)maxTokens;

/// Run inference with a prompt
/// - Parameter prompt: The input prompt for translation
/// - Returns: Generated text
- (NSString *)run:(NSString *)prompt;

/// Release resources
- (void)releaseResources;

@end

NS_ASSUME_NONNULL_END

