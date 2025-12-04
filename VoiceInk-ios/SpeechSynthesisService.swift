//
//  SpeechSynthesisService.swift
//  VoiceInk-ios
//
//  Centralized text-to-speech service following Single Responsibility Principle
//  Extracted from NoteRowView to make TTS reusable across the app
//

import Foundation
import AVFoundation
import SwiftUI

/// Service for text-to-speech synthesis
/// Follows KISS and Single Responsibility principles
@MainActor
class SpeechSynthesisService: ObservableObject {
    static let shared = SpeechSynthesisService()
    
    @Published var isSpeaking = false
    
    private var speechSynthesizer: AVSpeechSynthesizer?
    private var speechDelegate: SpeechDelegate?
    
    private init() {
        // Private initializer for singleton pattern
    }
    
    /// Speak text using AVSpeechSynthesizer with the appropriate language
    /// - Parameters:
    ///   - text: Text to speak
    ///   - language: Language code (e.g., "en", "es")
    func speak(_ text: String, language: String) {
        // Initialize synthesizer if needed
        if speechSynthesizer == nil {
            speechSynthesizer = AVSpeechSynthesizer()
        }
        
        guard let synthesizer = speechSynthesizer else { return }
        
        // Stop any current speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        // Create speech utterance with best available voice
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = findBestVoice(for: language)
        
        // Use natural speech rate and settings
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85 // Natural speaking pace
        utterance.pitchMultiplier = 1.0 // Natural pitch
        utterance.volume = 1.0
        
        // Set up delegate to track speaking state
        let delegate = SpeechDelegate { [weak self] newValue in
            Task { @MainActor in
                self?.isSpeaking = newValue
            }
        }
        speechDelegate = delegate // Store to prevent deallocation
        synthesizer.delegate = delegate
        
        // Start speaking
        isSpeaking = true
        synthesizer.speak(utterance)
    }
    
    /// Stop current speech
    func stop() {
        speechSynthesizer?.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
    
    /// Find the best available voice for a language, preferring enhanced (neural) voices
    private func findBestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        // Normalize language code (e.g., "en-US" -> "en")
        let languagePrefix = String(language.prefix(2))
        
        // Get all available voices for the language
        let availableVoices = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            voice.language.hasPrefix(languagePrefix)
        }
        
        // Prefer enhanced voices (neural TTS - sounds more natural)
        if #available(iOS 13.0, *) {
            if let enhancedVoice = availableVoices.first(where: { $0.quality == .enhanced }) {
                return enhancedVoice
            }
        }
        
        // Fall back to premium voices if available
        if #available(iOS 13.0, *) {
            if let premiumVoice = availableVoices.first(where: { $0.quality == .premium }) {
                return premiumVoice
            }
        }
        
        // Try to find any voice that matches the language exactly
        if let exactMatch = availableVoices.first(where: { $0.language == language }) {
            return exactMatch
        }
        
        // Fall back to default voice for the language
        return AVSpeechSynthesisVoice(language: language)
    }
}

/// Delegate to track speech synthesizer state
private class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    let onStateChange: (Bool) -> Void
    
    init(onStateChange: @escaping (Bool) -> Void) {
        self.onStateChange = onStateChange
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        onStateChange(true)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onStateChange(false)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onStateChange(false)
    }
}

