//
//  APIKeyManager.swift
//  VoiceInk-ios
//
//  API key management service extracted from AppSettings
//  Follows Single Responsibility Principle - handles API key storage and verification
//

import Foundation
import Combine

/// Manages API keys for various providers using secure Keychain storage
@MainActor
class APIKeyManager: ObservableObject {
    static let shared = APIKeyManager()
    
    // Dictionary-based storage for API keys (DRY principle)
    // Note: We can't use @Published on dictionaries directly, so we'll use objectWillChange manually
    private var apiKeys: [Provider: String] = [:] {
        didSet { objectWillChange.send() }
    }
    private var keyVerificationStatus: [Provider: Bool] = [:] {
        didSet { objectWillChange.send() }
    }
    
    private init() {
        // Load API keys into dictionary
        let providers: [Provider] = [.groq, .openai, .deepgram, .cerebras, .gemini]
        for provider in providers {
            apiKeys[provider] = Self.loadAPIKey(forKey: provider.apiKeyUserDefaultsKey)
            keyVerificationStatus[provider] = UserDefaults.standard.bool(forKey: provider.verificationUserDefaultsKey)
        }
    }
    
    /// Get API key for a provider
    /// - Parameter provider: The provider to get the key for
    /// - Returns: The API key, or empty string if not set
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
    
    /// Set API key for a provider
    /// - Parameters:
    ///   - key: The API key to set
    ///   - provider: The provider to set the key for
    func setAPIKey(_ key: String, for provider: Provider) {
        switch provider {
        case .groq, .openai, .deepgram, .cerebras, .gemini:
            setAPIKeyValue(key, for: provider)
        case .local, .voiceink:
            break // These providers don't use API keys
        }
    }
    
    /// Check if API key is verified for a provider
    /// - Parameter provider: The provider to check
    /// - Returns: True if the key is verified and not empty
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
    
    /// Set verification status for a provider's API key
    /// - Parameters:
    ///   - verified: Whether the key is verified
    ///   - provider: The provider to set verification for
    func setKeyVerified(_ verified: Bool, for provider: Provider) {
        switch provider {
        case .groq, .openai, .deepgram, .cerebras, .gemini:
            keyVerificationStatus[provider] = verified
            UserDefaults.standard.set(verified, forKey: provider.verificationUserDefaultsKey)
        case .local, .voiceink:
            break // These providers don't need verification
        }
    }
    
    // MARK: - Private Helpers
    
    /// Helper to set API key value and save (DRY)
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
    
    /// Save API key to Keychain
    private func saveAPIKey(_ key: String, forKey account: String) {
        guard let data = key.data(using: .utf8) else { return }
        let status = KeychainService.save(key: account, data: data)
        if status != errSecSuccess {
            Logger.error("Error saving API key to keychain: \(status)", category: "APIKeyManager")
        }
    }
    
    /// Load API key from Keychain
    private static func loadAPIKey(forKey account: String) -> String {
        if let data = KeychainService.load(key: account), let key = String(data: data, encoding: .utf8) {
            return key
        }
        return ""
    }
    
    // MARK: - Backward Compatibility (for AppSettings)
    
    /// Published properties for backward compatibility (computed from dictionaries)
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
}

