//
//  LlamaBridge.mm
//  VoiceInk-ios
//
//  Objective-C++ bridge for llama.cpp
//

#import "LlamaBridge.h"

// Check if llama.h is available (when llama.xcframework is added)
#ifdef __has_include
    #if __has_include("llama.h")
        #define LLAMA_AVAILABLE 1
        #include "llama.h"
        #include <vector>
    #else
        #define LLAMA_AVAILABLE 0
    #endif
#else
    #define LLAMA_AVAILABLE 0
#endif

#if !LLAMA_AVAILABLE
// Placeholder types when llama.h is not available
typedef int llama_token;
typedef void* llama_model;
typedef void* llama_context;
struct llama_model_params {};
struct llama_context_params {};
struct llama_batch {};
#define llama_model_default_params() {}
#define llama_context_default_params() {}
#define llama_load_model_from_file(path, params) nullptr
#define llama_new_context_with_model(model, params) nullptr
#define llama_tokenize(ctx, text, len, tokens, max, add_bos, special) 0
#define llama_batch_get_one(tokens, n_tokens, n_past, logits) {}
#define llama_decode(ctx, batch) 0
#define llama_sample_token(ctx, candidates) 0
#define llama_token_eos(ctx) 0
#define llama_token_to_piece(ctx, token, buf, len, special) 0
#define llama_free(ctx) {}
#define llama_free_model(model) {}
#endif

#include <string>
#include <vector>

@implementation LlamaBridge {
    llama_model * _Nullable model;
    llama_context * _Nullable ctx;
    int maxTokens;
}

- (instancetype)initWithModelPath:(NSString *)path context:(int)ctxSize tokens:(int)tok {
    self = [super init];
    if (self) {
        maxTokens = tok;
        
        #if LLAMA_AVAILABLE
        NSLog(@"LlamaBridge: Loading model from %@", path);
        
        struct llama_model_params mparams = llama_model_default_params();
        mparams.n_gpu_layers = 0; // Use CPU for now (can enable Metal later)
        
        model = llama_load_model_from_file([path UTF8String], &mparams);
        if (!model) {
            NSLog(@"LlamaBridge: Failed to load model");
            return nil;
        }
        
        NSLog(@"LlamaBridge: Model loaded successfully");
        
        struct llama_context_params cparams = llama_context_default_params();
        cparams.n_ctx = ctxSize;
        cparams.n_threads = 4; // Use 4 threads by default
        cparams.n_threads_batch = 4;
        cparams.seed = arc4random();
        
        ctx = llama_new_context_with_model(model, &cparams);
        if (!ctx) {
            NSLog(@"LlamaBridge: Failed to create context");
            llama_free_model(model);
            model = nil;
            return nil;
        }
        
        NSLog(@"LlamaBridge: Context created with size: %d, threads: %d", ctxSize, 4);
        #else
        NSLog(@"LlamaBridge: llama.h not available - using placeholder");
        #endif
    }
    return self;
}

- (NSString *)run:(NSString *)prompt {
    #if LLAMA_AVAILABLE
    if (!ctx) {
        NSLog(@"LlamaBridge: Context not initialized");
        return @"";
    }
    
    NSLog(@"LlamaBridge: Running inference with prompt length: %lu", (unsigned long)prompt.length);
    
    // Tokenize the prompt
    std::vector<llama_token> tokens;
    tokens.resize(prompt.length() + 1);
    
    int n_tokens = llama_tokenize(ctx, [prompt UTF8String], (int)prompt.length, tokens.data(), (int)tokens.size(), true, false);
    if (n_tokens < 0) {
        tokens.resize(-n_tokens);
        n_tokens = llama_tokenize(ctx, [prompt UTF8String], (int)prompt.length, tokens.data(), (int)tokens.size(), true, false);
    }
    
    if (n_tokens <= 0) {
        NSLog(@"LlamaBridge: Failed to tokenize prompt");
        return @"";
    }
    
    tokens.resize(n_tokens);
    
    // Evaluate the prompt
    if (llama_decode(ctx, llama_batch_get_one(tokens.data(), n_tokens, 0, 0)) != 0) {
        NSLog(@"LlamaBridge: Failed to evaluate prompt");
        return @"";
    }
    
    // Generate tokens
    std::string result;
    int n_cur = n_tokens;
    int n_decode = 0;
    
    while (n_cur < n_tokens + maxTokens) {
        // Sample the next token
        llama_token new_token_id = llama_sample_token(ctx, nullptr);
        
        if (new_token_id == llama_token_eos(ctx)) {
            break;
        }
        
        // Decode token to string
        char piece[8];
        int n_piece = llama_token_to_piece(ctx, new_token_id, piece, sizeof(piece), false);
        if (n_piece > 0) {
            result += std::string(piece, n_piece);
        }
        
        // Evaluate the new token
        if (llama_decode(ctx, llama_batch_get_one(&new_token_id, 1, n_cur, 0)) != 0) {
            break;
        }
        
        n_cur++;
        n_decode++;
    }
    
    NSString *output = [NSString stringWithUTF8String:result.c_str()];
    NSLog(@"LlamaBridge: Generated %d tokens, text length: %lu", n_decode, (unsigned long)output.length);
    
    return output ?: @"";
    #else
    NSLog(@"LlamaBridge: llama.h not available - returning placeholder");
    return @"[Translation requires llama.cpp framework]";
    #endif
}

- (void)releaseResources {
    #if LLAMA_AVAILABLE
    if (ctx) {
        llama_free(ctx);
        ctx = nil;
    }
    if (model) {
        llama_free_model(model);
        model = nil;
    }
    NSLog(@"LlamaBridge: Resources released");
    #endif
}

- (void)dealloc {
    [self releaseResources];
}

@end

