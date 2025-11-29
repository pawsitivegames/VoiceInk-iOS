import Foundation
#if canImport(MLKitTranslate)
@preconcurrency import MLKitTranslate
#endif

struct TranslationService {
    #if canImport(MLKitTranslate)
    // Cache translator instances as static properties (performance optimization)
    // Using static to avoid struct mutability issues
    private static var cachedTranslator: Translator? = {
        let options = TranslatorOptions(sourceLanguage: .english, targetLanguage: .spanish)
        return Translator.translator(options: options)
    }()
    
    private static var cachedTranslatorSpanishToEnglish: Translator? = {
        let options = TranslatorOptions(sourceLanguage: .spanish, targetLanguage: .english)
        return Translator.translator(options: options)
    }()
    
    // Helper to get translator instances
    private var translator: Translator? {
        Self.cachedTranslator
    }
    
    private var translatorSpanishToEnglish: Translator? {
        Self.cachedTranslatorSpanishToEnglish
    }
    #endif
    
    private let client = OpenAICompatibleClient()
    
    /// Translates English text to Spanish using ML Kit On-Device Translation with API fallback
    /// 
    /// This uses Google ML Kit for on-device translation, which is free,
    /// works offline, and doesn't require API keys or external dependencies.
    /// Falls back to LLM API if ML Kit is not available.
    func translateToSpanish(text: String) async throws -> String {
        return try await translate(
            text: text,
            sourceLanguage: "English",
            targetLanguage: "Spanish",
            mlKitTranslator: translator,
            systemPrompt: "You are a professional translator. Translate the following English text to Spanish. Only return the Spanish translation, nothing else.",
            userPromptPrefix: "Translate this to Spanish:"
        )
    }
    
    /// Translates Spanish text to English using ML Kit On-Device Translation with API fallback
    /// 
    /// This uses Google ML Kit for on-device translation, which is free,
    /// works offline, and doesn't require API keys or external dependencies.
    /// Falls back to LLM API if ML Kit is not available.
    func translateToEnglish(text: String) async throws -> String {
        return try await translate(
            text: text,
            sourceLanguage: "Spanish",
            targetLanguage: "English",
            mlKitTranslator: translatorSpanishToEnglish,
            systemPrompt: "You are a professional translator. Translate the following Spanish text to English. Only return the English translation, nothing else.",
            userPromptPrefix: "Translate this to English:"
        )
    }
    
    // MARK: - Common Translation Logic (DRY principle)
    
    /// Common translation method that handles both ML Kit and LLM API fallback
    private func translate(
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        mlKitTranslator: Translator?,
        systemPrompt: String,
        userPromptPrefix: String
    ) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Logger.warning("Empty text provided", category: "TranslationService")
            return ""
        }
        
        Logger.debug("Starting \(sourceLanguage)→\(targetLanguage) translation, text length: \(text.count)", category: "TranslationService")
        
        #if canImport(MLKitTranslate)
        // Try ML Kit first (on-device, offline)
        if let translator = mlKitTranslator {
            do {
                let translated = try await translateWithMLKit(text: text, translator: translator, direction: "\(sourceLanguage)→\(targetLanguage)")
                if !translated.isEmpty {
                    return translated
                }
                Logger.warning("ML Kit returned empty string, falling back to LLM API", category: "TranslationService")
            } catch {
                Logger.warning("ML Kit translation failed: \(error.localizedDescription), falling back to LLM API", category: "TranslationService")
            }
        }
        #endif
        
        // Fallback to LLM API
        Logger.debug("Using LLM API fallback", category: "TranslationService")
        do {
            return try await translateWithLLMAPI(text: text, systemPrompt: systemPrompt, userPromptPrefix: userPromptPrefix)
        } catch {
            // Ensure error is properly propagated with context
            Logger.error("LLM API translation also failed: \(error.localizedDescription)", category: "TranslationService")
            throw TranslationError.translationFailed("Both ML Kit and LLM API translation failed. LLM API error: \(error.localizedDescription)")
        }
    }
    
    #if canImport(MLKitTranslate)
    /// Translate using ML Kit On-Device Translation (offline, free)
    /// Performance: Adds timeout to model download to fail fast and fall back to LLM API
    private func translateWithMLKit(text: String, translator: Translator, direction: String) async throws -> String {
        Logger.debug("Using ML Kit On-Device Translation (\(direction))", category: "TranslationService")
        
        // Download model if needed (with conditions)
        let conditions = ModelDownloadConditions(
            allowsCellularAccess: false, // Only download on WiFi
            allowsBackgroundDownloading: true
        )
        
        // Add timeout to model download (5 seconds) to fail fast and fall back to LLM API
        return try await withThrowingTaskGroup(of: String.self) { group in
            // Model download and translation task
            group.addTask {
                return try await withCheckedThrowingContinuation { continuation in
                    translator.downloadModelIfNeeded(with: conditions) { error in
                        if let error = error {
                            Logger.warning("ML Kit model download failed: \(error.localizedDescription)", category: "TranslationService")
                            continuation.resume(throwing: TranslationError.translationFailed("Model download failed: \(error.localizedDescription)"))
                            return
                        }
                        
                        Logger.debug("ML Kit model ready", category: "TranslationService")
                        
                        // Translate text
                        translator.translate(text) { translatedText, error in
                            if let error = error {
                                Logger.error("ML Kit translation failed: \(error.localizedDescription)", category: "TranslationService")
                                continuation.resume(throwing: TranslationError.translationFailed(error.localizedDescription))
                                return
                            }
                            
                            guard let translatedText = translatedText else {
                                continuation.resume(throwing: TranslationError.translationFailed("Translation returned nil"))
                                return
                            }
                            
                            Logger.info("ML Kit translation successful! Length: \(translatedText.count)", category: "TranslationService")
                            continuation.resume(returning: translatedText)
                        }
                    }
                }
            }
            
            // Timeout task (5 seconds for model download)
            group.addTask {
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                throw TranslationError.translationFailed("ML Kit model download timed out")
            }
            
            // Get first result (either translation or timeout)
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    #endif
    
    /// Translate using LLM API (fallback)
    private func translateWithLLMAPI(text: String, systemPrompt: String, userPromptPrefix: String) async throws -> String {
        let settings = AppSettings.shared
        
        guard let llmConfig = settings.findAvailableLLMProvider() else {
            Logger.error("No LLM provider available for translation", category: "TranslationService")
            throw TranslationError.translatorUnavailable
        }
        
        Logger.debug("Using LLM provider: \(llmConfig.provider.rawValue), model: \(llmConfig.model)", category: "TranslationService")
        
        let userPrompt = "\(userPromptPrefix) \(text)"
        let messages = [
            OAChatMessage(role: "system", content: systemPrompt),
            OAChatMessage(role: "user", content: userPrompt)
        ]
        
        let result = try await client.chatCompletion(
            baseURL: llmConfig.provider.baseURL,
            apiKey: llmConfig.apiKey,
            model: llmConfig.model,
            messages: messages,
            temperature: 0.3
        )
        
        let translated = result.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.info("API translation successful! Length: \(translated.count)", category: "TranslationService")
        return translated
    }
}

enum TranslationError: LocalizedError {
    case translatorUnavailable
    case unsupportedVersion
    case translationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .translatorUnavailable:
            return "Translation service is not available. Please ensure your device supports translation."
        case .unsupportedVersion:
            return "Translation requires iOS 18.0 or later. Please update your device."
        case .translationFailed(let message):
            return "Translation failed: \(message)"
        }
    }
}

