import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // Modes system
    @Published var modes: [Mode] {
        didSet { saveModes() }
    }
    
    @Published var selectedModeId: UUID? {
        didSet { 
            if let id = selectedModeId {
                UserDefaults.standard.set(id.uuidString, forKey: "selectedModeId")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedModeId")
            }
        }
    }
    
    var selectedMode: Mode? {
        guard let selectedModeId = selectedModeId else { return nil }
        return modes.first { $0.id == selectedModeId }
    }



    // Dictionary-based storage for API keys (DRY principle)
    // Note: We can't use @Published on dictionaries directly, so we'll use objectWillChange manually
    private var apiKeys: [Provider: String] = [:] {
        didSet { objectWillChange.send() }
    }
    private var keyVerificationStatus: [Provider: Bool] = [:] {
        didSet { objectWillChange.send() }
    }
    
    // Published properties for backward compatibility (computed from dictionaries)
    var groqAPIKey: String {
        get { apiKeys[.groq] ?? "" }
        set { setAPIKeyValue(newValue, for: .groq) }
    }

    var openAIAPIKey: String {
        get { apiKeys[.openai] ?? "" }
        set { setAPIKeyValue(newValue, for: .openai) }
    }

    var deepgramAPIKey: String {
        get { apiKeys[.deepgram] ?? "" }
        set { setAPIKeyValue(newValue, for: .deepgram) }
    }

    var cerebrasAPIKey: String {
        get { apiKeys[.cerebras] ?? "" }
        set { setAPIKeyValue(newValue, for: .cerebras) }
    }

    var geminiAPIKey: String {
        get { apiKeys[.gemini] ?? "" }
        set { setAPIKeyValue(newValue, for: .gemini) }
    }
    
    // Published properties for verification status (computed from dictionaries)
    var groqKeyVerified: Bool {
        get { keyVerificationStatus[.groq] ?? false }
        set { keyVerificationStatus[.groq] = newValue; UserDefaults.standard.set(newValue, forKey: "groqKeyVerified") }
    }
    
    var openAIKeyVerified: Bool {
        get { keyVerificationStatus[.openai] ?? false }
        set { keyVerificationStatus[.openai] = newValue; UserDefaults.standard.set(newValue, forKey: "openAIKeyVerified") }
    }

    var deepgramKeyVerified: Bool {
        get { keyVerificationStatus[.deepgram] ?? false }
        set { keyVerificationStatus[.deepgram] = newValue; UserDefaults.standard.set(newValue, forKey: "deepgramKeyVerified") }
    }

    var cerebrasKeyVerified: Bool {
        get { keyVerificationStatus[.cerebras] ?? false }
        set { keyVerificationStatus[.cerebras] = newValue; UserDefaults.standard.set(newValue, forKey: "cerebrasKeyVerified") }
    }

    var geminiKeyVerified: Bool {
        get { keyVerificationStatus[.gemini] ?? false }
        set { keyVerificationStatus[.gemini] = newValue; UserDefaults.standard.set(newValue, forKey: "geminiKeyVerified") }
    }
    
    // Helper to set API key value and save (DRY)
    private func setAPIKeyValue(_ value: String, for provider: Provider) {
        let oldValue = apiKeys[provider] ?? ""
        apiKeys[provider] = value
        saveAPIKey(value, forKey: provider.apiKeyUserDefaultsKey)
        // Reset verification if key changed
        if oldValue != value {
            keyVerificationStatus[provider] = false
            UserDefaults.standard.set(false, forKey: provider.verificationUserDefaultsKey)
        }
    }
    
    // Audio session timeout configuration
    @Published var audioSessionTimeoutSeconds: Int {
        didSet { UserDefaults.standard.set(audioSessionTimeoutSeconds, forKey: "audioSessionTimeoutSeconds") }
    }


    private init() {
        // Load modes
        self.modes = Self.loadModes()
        
        // Load selected mode
        if let selectedModeIdString = UserDefaults.standard.string(forKey: "selectedModeId"),
           let selectedModeId = UUID(uuidString: selectedModeIdString) {
            self.selectedModeId = selectedModeId
        } else {
            self.selectedModeId = nil
        }
        

        // Load API keys into dictionary
        let providers: [Provider] = [.groq, .openai, .deepgram, .cerebras, .gemini]
        for provider in providers {
            apiKeys[provider] = AppSettings.loadAPIKey(forKey: provider.apiKeyUserDefaultsKey)
            keyVerificationStatus[provider] = UserDefaults.standard.bool(forKey: provider.verificationUserDefaultsKey)
        }
        
        // Load audio session timeout (default: 90 seconds)
        self.audioSessionTimeoutSeconds = UserDefaults.standard.object(forKey: "audioSessionTimeoutSeconds") as? Int ?? 90

    }

    func apiKey(for provider: Provider) -> String {
        switch provider {
        case .groq, .openai, .deepgram, .cerebras, .gemini:
            return apiKeys[provider] ?? ""
        case .local:
            return "local" // Local transcription doesn't need an API key
        case .voiceink:
            return "" // TODO: Replace with actual VoiceInk API key
        }
    }

    func setAPIKey(_ key: String, for provider: Provider) {
        switch provider {
        case .groq, .openai, .deepgram, .cerebras, .gemini:
            setAPIKeyValue(key, for: provider)
        case .local, .voiceink:
            break // These providers don't use API keys
        }
    }
    
    func isKeyVerified(for provider: Provider) -> Bool {
        switch provider {
        case .groq, .openai, .deepgram, .cerebras, .gemini:
            let key = apiKeys[provider] ?? ""
            let verified = keyVerificationStatus[provider] ?? false
            return verified && !key.isEmpty
        case .local:
            return LocalModelManager.shared.hasAvailableModel
        case .voiceink:
            return true // VoiceInk uses hardcoded API key, always verified
        }
    }
    
    func setKeyVerified(_ verified: Bool, for provider: Provider) {
        switch provider {
        case .groq, .openai, .deepgram, .cerebras, .gemini:
            keyVerificationStatus[provider] = verified
            UserDefaults.standard.set(verified, forKey: provider.verificationUserDefaultsKey)
        case .local, .voiceink:
            break // These providers don't need verification
        }
    }


    // MARK: - Modes Management
    
    // Debounce saves to avoid excessive UserDefaults writes
    private var saveModesWorkItem: DispatchWorkItem?
    
    private func saveModes() {
        // Cancel any pending save
        saveModesWorkItem?.cancel()
        
        // Schedule save after a short delay to batch multiple rapid changes
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if let data = try? JSONEncoder().encode(self.modes) {
                UserDefaults.standard.set(data, forKey: "modes")
            }
        }
        saveModesWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }
    
    deinit {
        // Ensure pending saves complete
        saveModesWorkItem?.perform()
    }
    
    private static func loadModes() -> [Mode] {
        guard let data = UserDefaults.standard.data(forKey: "modes"),
              let modes = try? JSONDecoder().decode([Mode].self, from: data) else {
            return []
        }
        return modes
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

    private func saveAPIKey(_ key: String, forKey account: String) {
        guard let data = key.data(using: .utf8) else { return }
        let status = KeychainService.save(key: account, data: data)
        if status != errSecSuccess {
            Logger.error("Error saving API key to keychain: \(status)", category: "AppSettings")
        }
    }
    
    private static func loadAPIKey(forKey account: String) -> String {
        if let data = KeychainService.load(key: account), let key = String(data: data, encoding: .utf8) {
            return key
        }
        return ""
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


