import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // Mode management delegated to ModeManager
    let modeManager = ModeManager.shared
    
    // Published properties for backward compatibility (delegated to ModeManager)
    var modes: [Mode] {
        get { modeManager.modes }
        set { modeManager.modes = newValue }
    }
    
    var selectedModeId: UUID? {
        get { modeManager.selectedModeId }
        set { modeManager.selectedModeId = newValue }
    }
    
    var selectedMode: Mode? {
        return modeManager.selectedMode
    }



    // API key management delegated to APIKeyManager
    let apiKeyManager = APIKeyManager.shared
    
    // Published properties for backward compatibility (delegated to APIKeyManager)
    var groqAPIKey: String {
        get { apiKeyManager.groqAPIKey }
        set { apiKeyManager.groqAPIKey = newValue }
    }

    var openAIAPIKey: String {
        get { apiKeyManager.openAIAPIKey }
        set { apiKeyManager.openAIAPIKey = newValue }
    }

    var deepgramAPIKey: String {
        get { apiKeyManager.deepgramAPIKey }
        set { apiKeyManager.deepgramAPIKey = newValue }
    }

    var cerebrasAPIKey: String {
        get { apiKeyManager.cerebrasAPIKey }
        set { apiKeyManager.cerebrasAPIKey = newValue }
    }

    var geminiAPIKey: String {
        get { apiKeyManager.geminiAPIKey }
        set { apiKeyManager.geminiAPIKey = newValue }
    }
    
    // Published properties for verification status (delegated to APIKeyManager)
    var groqKeyVerified: Bool {
        get { apiKeyManager.groqKeyVerified }
        set { apiKeyManager.groqKeyVerified = newValue }
    }
    
    var openAIKeyVerified: Bool {
        get { apiKeyManager.openAIKeyVerified }
        set { apiKeyManager.openAIKeyVerified = newValue }
    }

    var deepgramKeyVerified: Bool {
        get { apiKeyManager.deepgramKeyVerified }
        set { apiKeyManager.deepgramKeyVerified = newValue }
    }

    var cerebrasKeyVerified: Bool {
        get { apiKeyManager.cerebrasKeyVerified }
        set { apiKeyManager.cerebrasKeyVerified = newValue }
    }

    var geminiKeyVerified: Bool {
        get { apiKeyManager.geminiKeyVerified }
        set { apiKeyManager.geminiKeyVerified = newValue }
    }
    
    // Audio session timeout configuration
    @Published var audioSessionTimeoutSeconds: Int {
        didSet { UserDefaults.standard.set(audioSessionTimeoutSeconds, forKey: "audioSessionTimeoutSeconds") }
    }
    
    // Language configuration
    @Published var languageConfiguration: LanguageConfiguration {
        didSet { saveLanguageConfiguration() }
    }

    private init() {
        // Modes are loaded by ModeManager.shared during initialization
        // API keys are loaded by APIKeyManager.shared during initialization
        
        // Load audio session timeout (default: 90 seconds)
        self.audioSessionTimeoutSeconds = UserDefaults.standard.object(forKey: "audioSessionTimeoutSeconds") as? Int ?? 90
        
        // Load language configuration (default: English to Spanish)
        self.languageConfiguration = Self.loadLanguageConfiguration()

    }

    func apiKey(for provider: Provider) -> String {
        return apiKeyManager.apiKey(for: provider)
    }

    func setAPIKey(_ key: String, for provider: Provider) {
        apiKeyManager.setAPIKey(key, for: provider)
    }
    
    func isKeyVerified(for provider: Provider) -> Bool {
        return apiKeyManager.isKeyVerified(for: provider)
    }
    
    func setKeyVerified(_ verified: Bool, for provider: Provider) {
        apiKeyManager.setKeyVerified(verified, for: provider)
    }


    
    // MARK: - Mode-based Settings
    
    /// Get the effective transcription provider (from selected mode or first mode)
    var effectiveTranscriptionProvider: Provider {
        if let selectedMode = selectedMode {
            return selectedMode.transcriptionProvider
        } else if let firstMode = modes.first {
            return firstMode.transcriptionProvider
        } else {
            return .groq // Default fallback
        }
    }
    
    /// Get the effective transcription model (from selected mode or first mode)
    var effectiveTranscriptionModel: String {
        if let selectedMode = selectedMode {
            return selectedMode.transcriptionProvider == .voiceink ? voiceInkTranscriptionModel() : selectedMode.transcriptionModel
        } else if let firstMode = modes.first {
            return firstMode.transcriptionProvider == .voiceink ? voiceInkTranscriptionModel() : firstMode.transcriptionModel
        } else {
            return effectiveTranscriptionProvider == .voiceink ? voiceInkTranscriptionModel() : "whisper-large-v3" // Default fallback
        }
    }
    
    /// Get the effective post-processing provider (from selected mode or first mode)
    var effectivePostProcessingProvider: Provider {
        if let selectedMode = selectedMode {
            return selectedMode.postProcessingProvider
        } else if let firstMode = modes.first {
            return firstMode.postProcessingProvider
        } else {
            return .groq // Default fallback
        }
    }
    
    /// Get the effective post-processing model (from selected mode or first mode)
    var effectivePostProcessingModel: String {
        if let selectedMode = selectedMode {
            return selectedMode.postProcessingProvider == .voiceink ? voiceInkPostProcessingModel() : selectedMode.postProcessingModel
        } else if let firstMode = modes.first {
            return firstMode.postProcessingProvider == .voiceink ? voiceInkPostProcessingModel() : firstMode.postProcessingModel
        } else {
            return effectivePostProcessingProvider == .voiceink ? voiceInkPostProcessingModel() : "llama-3.1-8b-instant" // Default fallback
        }
    }
    
    /// Get the effective custom prompt (from selected mode or first mode)
    var effectiveCustomPrompt: String {
        if let selectedMode = selectedMode {
            return selectedMode.effectivePrompt
        } else if let firstMode = modes.first {
            return firstMode.effectivePrompt
        } else {
            return "" // Default fallback
        }
    }
    
    /// Get whether post-processing is enabled (from selected mode or first mode)
    var effectiveIsPostProcessingEnabled: Bool {
        if let selectedMode = selectedMode {
            return selectedMode.isPostProcessingEnabled
        } else if let firstMode = modes.first {
            return firstMode.isPostProcessingEnabled
        } else {
            return false // Default fallback
        }
    }
    
    // MARK: - VoiceInk Hardcoded Models
    
    /// Get the hardcoded transcription model for VoiceInk
    func voiceInkTranscriptionModel() -> String {
        return "whisper-large-v3"
    }
    
    /// Get the hardcoded post-processing model for VoiceInk
    func voiceInkPostProcessingModel() -> String {
        return "openai/gpt-oss-120b"
    }
    
    // MARK: - Translation Provider Selection
    
    /// Finds an available LLM provider for translation (one that supports LLM and has an API key)
    func findAvailableLLMProvider() -> (provider: Provider, apiKey: String, model: String)? {
        // First, try the post-processing provider if it supports LLM
        let postProcessingProvider = effectivePostProcessingProvider
        if postProcessingProvider.supportsLLM {
            let apiKey = self.apiKey(for: postProcessingProvider)
            if !apiKey.isEmpty {
                let model = effectivePostProcessingModel
                return (postProcessingProvider, apiKey, model)
            }
        }
        
        // Otherwise, try other LLM providers in order of preference
        let preferredProviders: [Provider] = [.groq, .openai, .cerebras, .gemini, .voiceink]
        for provider in preferredProviders {
            if provider.supportsLLM {
                let apiKey = self.apiKey(for: provider)
                if !apiKey.isEmpty {
                    // Get the first available model for this provider
                    let models = provider.models(for: .postProcessing)
                    if let firstModel = models.first {
                        return (provider, apiKey, firstModel)
                    }
                }
            }
        }
        
        return nil
    }


    // MARK: - Language Configuration
    
    private func saveLanguageConfiguration() {
        if let data = try? JSONEncoder().encode(languageConfiguration) {
            UserDefaults.standard.set(data, forKey: "languageConfiguration")
        }
    }
    
    private static func loadLanguageConfiguration() -> LanguageConfiguration {
        guard let data = UserDefaults.standard.data(forKey: "languageConfiguration"),
              let config = try? JSONDecoder().decode(LanguageConfiguration.self, from: data) else {
            // Default: English to Spanish (backward compatible)
            return LanguageConfiguration(sourceLanguageCode: "en", targetLanguageCode: "es")
        }
        return config
    }
    
    // MARK: - Debug Reset
    /// Remove all persisted preferences, API keys, and modes.
    func resetAll() {
        // Clear modes and selection
        modes = []
        selectedModeId = nil
        UserDefaults.standard.removeObject(forKey: "modes")
        UserDefaults.standard.removeObject(forKey: "selectedModeId")
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")

        // Clear verification flags
        groqKeyVerified = false
        openAIKeyVerified = false
        deepgramKeyVerified = false
        cerebrasKeyVerified = false
        geminiKeyVerified = false
        UserDefaults.standard.removeObject(forKey: "groqKeyVerified")
        UserDefaults.standard.removeObject(forKey: "openAIKeyVerified")
        UserDefaults.standard.removeObject(forKey: "deepgramKeyVerified")
        UserDefaults.standard.removeObject(forKey: "cerebrasKeyVerified")
        UserDefaults.standard.removeObject(forKey: "geminiKeyVerified")
        
        // Reset audio session timeout to default
        audioSessionTimeoutSeconds = 90
        UserDefaults.standard.removeObject(forKey: "audioSessionTimeoutSeconds")
        
        // Reset language configuration to default
        languageConfiguration = LanguageConfiguration(sourceLanguageCode: "en", targetLanguageCode: "es")
        UserDefaults.standard.removeObject(forKey: "languageConfiguration")

        // Clear API keys from memory and Keychain
        groqAPIKey = ""
        openAIAPIKey = ""
        deepgramAPIKey = ""
        cerebrasAPIKey = ""
        geminiAPIKey = ""
        _ = KeychainService.delete(key: "groqAPIKey")
        _ = KeychainService.delete(key: "openAIAPIKey")
        _ = KeychainService.delete(key: "deepgramAPIKey")
        _ = KeychainService.delete(key: "cerebrasAPIKey")
        _ = KeychainService.delete(key: "geminiAPIKey")
    }
}

// MARK: - Language Configuration Convenience Methods
// Extension to fix Law of Demeter violations by providing direct access to language configuration properties

extension AppSettings {
    /// Source language code (language user speaks)
    var sourceLanguageCode: String {
        languageConfiguration.sourceLanguageCode
    }
    
    /// Target language code (language user wants to learn/translate to)
    var targetLanguageCode: String {
        languageConfiguration.targetLanguageCode
    }
    
    /// Returns the opposite language code for translation direction
    /// - Parameter detectedLang: Detected language code (e.g., "en", "es")
    /// - Returns: Opposite language code based on current configuration
    func oppositeLanguageCode(for detectedLang: String?) -> String {
        languageConfiguration.oppositeLanguageCode(for: detectedLang)
    }
}


