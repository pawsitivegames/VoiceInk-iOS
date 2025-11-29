import SwiftUI
import UIKit
import AVFoundation

struct NoteRowView: View {
    let note: Transcription
    // Callbacks removed since star/share are gone
    let onToggleStar: () -> Void = {}
    let onToggleShare: () -> Void = {}
    
    @State private var showCopyToast = false
    @State private var copyToastMessage = ""
    @State private var speechSynthesizer: AVSpeechSynthesizer?
    @State private var speechDelegate: SpeechDelegate?
    @State private var isSpeaking = false
    @State private var stateHolder = SpeakingStateHolder()
    
    // Cache note data in @State to avoid accessing SwiftData properties during view body evaluation
    // This prevents crashes when the model is being updated or invalidated
    @State private var cachedNoteData: NoteData?
    
    // Helper struct to hold cached note data
    private struct NoteData {
        let transcriptionStatus: TranscriptionStatus
        let detectedLanguage: String?
        let translatedText: String?
        let translatedLanguageCode: String?
        let enhancedText: String?
        let text: String
        let duration: TimeInterval
        let timestamp: Date
        
        init(from note: Transcription) {
            // Access all properties in one atomic operation
            // This minimizes the window where SwiftData might invalidate the model
            self.transcriptionStatus = note.transcriptionStatus
            self.detectedLanguage = note.detectedLanguage
            self.translatedText = note.translatedText
            self.translatedLanguageCode = note.translatedLanguageCode
            self.enhancedText = note.enhancedText
            self.text = note.text
            self.duration = note.duration
            self.timestamp = note.timestamp
        }
    }
    
    // Helper function to get transcript text based on status
    // This avoids accessing SwiftData properties multiple times
    private func transcriptText(for status: TranscriptionStatus, enhancedText: String?, text: String) -> String {
        switch status {
        case .pending:
            return "Processing translation..."
        case .failed:
            return "Transcription failed - tap to retry"
        case .completed:
            // Prioritize enhanced text (post-processed result) over original text
            if let enhancedText = enhancedText, !enhancedText.isEmpty {
                return enhancedText
            } else if !text.isEmpty {
                return text
            } else {
                return "No audible content detected."
            }
        }
    }
    
    @StateObject private var settings = AppSettings.shared
    
    // Helper functions to get language info - now take cached values as parameters
    private func languageInfo(for detectedLang: String?) -> (flag: String, label: String) {
        if let detectedLang = detectedLang {
            let langCode = detectedLang
            return (LanguageHelper.flag(for: langCode), LanguageHelper.languageName(for: langCode))
        }
        // Default to source language
        let sourceCode = settings.languageConfiguration.sourceLanguageCode
        return (LanguageHelper.flag(for: sourceCode), LanguageHelper.languageName(for: sourceCode))
    }
    
    private func translationInfo(for detectedLang: String?, translatedLanguageCode: String?) -> (flag: String, label: String) {
        // Use stored translatedLanguageCode if available (preserves original translation language)
        if let storedCode = translatedLanguageCode {
            return (LanguageHelper.flag(for: storedCode), LanguageHelper.languageName(for: storedCode))
        }
        // Fallback to calculating from current language configuration (for backward compatibility)
        if let detectedLang = detectedLang {
            let oppositeCode = settings.languageConfiguration.oppositeLanguageCode(for: detectedLang)
            return (LanguageHelper.flag(for: oppositeCode), LanguageHelper.languageName(for: oppositeCode))
        }
        // Default translation to target language
        let targetCode = settings.languageConfiguration.targetLanguageCode
        return (LanguageHelper.flag(for: targetCode), LanguageHelper.languageName(for: targetCode))
    }
    
    // Helper function to get relative timestamp string
    private func relativeTimestampString(for timestamp: Date) -> String {
        return timestamp.relativeTimeString
    }

    var body: AnyView {
        // Use cached note data to avoid accessing SwiftData properties during view body evaluation
        // If cache is not available yet, show a loading state
        guard let noteData = cachedNoteData else {
            return AnyView(
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("🌐")
                            .font(.title3)
                        Text("Loading...")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear {
                    // Extract and cache note data when view appears
                    cachedNoteData = NoteData(from: note)
                }
            )
        }
        
        // Use the cached data
        let transcriptionStatus = noteData.transcriptionStatus
        let detectedLanguage = noteData.detectedLanguage
        let translatedText = noteData.translatedText
        let translatedLanguageCode = noteData.translatedLanguageCode
        let enhancedText = noteData.enhancedText
        let noteText = noteData.text
        let noteDuration = noteData.duration
        let noteTimestamp = noteData.timestamp
        let transcriptText = transcriptText(for: transcriptionStatus, enhancedText: enhancedText, text: noteText)
        
        // Cache language info using the cached detectedLanguage
        let languageInfo = languageInfo(for: detectedLanguage)
        let translationInfo = translationInfo(for: detectedLanguage, translatedLanguageCode: translatedLanguageCode)
        let relativeTimestamp = relativeTimestampString(for: noteTimestamp)
        
        return AnyView(VStack(alignment: .leading, spacing: 0) {
                // Main content area
                VStack(alignment: .leading, spacing: 0) {
                    // Original language (detected) - tappable to copy
                    if transcriptionStatus == .completed {
                    HStack(alignment: .top, spacing: 8) {
                        // Flag button - tappable for text-to-speech
                        Button(action: {
                            let detectedLang = detectedLanguage ?? settings.languageConfiguration.sourceLanguageCode
                            speakText(transcriptText, language: LanguageHelper.localeCode(for: detectedLang))
                        }) {
                            Text(languageInfo.flag)
                                .font(.title3)
                                .opacity(isSpeaking ? 0.6 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(languageInfo.label) flag")
                        .accessibilityHint("Double tap to hear \(languageInfo.label) pronunciation")
                        
                        // Text button - tappable to copy
                        Button(action: {
                            let englishText = enhancedText ?? noteText
                            copyToClipboardWithMessage(englishText, message: "\(languageInfo.label) copied")
                        }) {
                            Text(transcriptText)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(languageInfo.label) text: \(transcriptText)")
                    .accessibilityHint("Double tap text to copy, or double tap flag to hear pronunciation")
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        Text(languageInfo.flag)
                            .font(.title3)
                        
                        Text(transcriptText)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Translation (opposite language) - tappable to copy
                if let translatedText = translatedText, !translatedText.isEmpty, transcriptionStatus == .completed {
                    Divider()
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                    
                    HStack(alignment: .top, spacing: 8) {
                        // Flag button - tappable for text-to-speech
                        Button(action: {
                            // Use stored translatedLanguageCode if available, otherwise calculate from current settings
                            let targetCode = translatedLanguageCode ?? {
                                let detectedLang = detectedLanguage ?? settings.languageConfiguration.sourceLanguageCode
                                return settings.languageConfiguration.oppositeLanguageCode(for: detectedLang)
                            }()
                            speakText(translatedText, language: LanguageHelper.localeCode(for: targetCode))
                        }) {
                            Text(translationInfo.flag)
                                .font(.title3)
                                .opacity(isSpeaking ? 0.6 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(translationInfo.label) flag")
                        .accessibilityHint("Double tap to hear \(translationInfo.label) pronunciation")
                        
                        // Text button - tappable to copy
                        Button(action: {
                            copyToClipboardWithMessage(translatedText, message: "\(translationInfo.label) copied")
                        }) {
                            Text(translatedText)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(translationInfo.label) translation: \(translatedText)")
                    .accessibilityHint("Double tap text to copy, or double tap flag to hear pronunciation")
                }
            }

            // Footer metadata
            HStack(spacing: 8) {
                if noteDuration > 0 {
                    Text("\(relativeTimestamp) • \(noteDuration.formattedTimeString)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(relativeTimestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
                
                // Copy Both button - in footer row
                if transcriptionStatus == .completed, translatedText != nil, !(translatedText?.isEmpty ?? true) {
                    Button(action: {
                        copyAllText()
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.blue)
                            .padding(4)
                            .background(
                                Circle()
                                    .fill(Color.blue.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy both texts")
                    .accessibilityHint("Double tap to copy both the original and translated text")
                }

                if transcriptionStatus == .pending {
                    HStack(spacing: 6) {
                        // Custom SwiftUI-only loading indicator to avoid UIKit rendering issues
                        LoadingSpinner(color: .secondary, lineWidth: 1.5, size: 12)
                        Text("Processing")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Processing transcription")
                } else if transcriptionStatus == .failed {
                    Label("Failed", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Transcription failed")
                }
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if showCopyToast {
                copyToastView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.default, value: showCopyToast)
            }
        }
        .onAppear {
            // Update cache when view appears
            cachedNoteData = NoteData(from: note)
        }
        // OPTIMIZATION: Watch note.id instead of individual properties
        // This is more efficient and only triggers when the note instance changes
        // Individual property changes within the same note don't need cache refresh
        // since SwiftData handles those updates automatically
        .onChange(of: note.id) { _, _ in
            // Only update cache if note ID changes (new note instance)
            cachedNoteData = NoteData(from: note)
        }
        // Also watch for status changes that affect display
        .onChange(of: note.transcriptionStatus) { _, _ in
            // Update cache when status changes (pending -> completed)
            cachedNoteData = NoteData(from: note)
        })
    }
    

    private func copyToClipboardWithMessage(_ text: String, message: String = "Copied to clipboard") {
        _ = copyToClipboard(text)
        
        // Show toast
        copyToastMessage = message
        withAnimation {
            showCopyToast = true
        }
        
        // Hide toast after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showCopyToast = false
            }
        }
    }
    
    private func copyAllText() {
        // Use stored translatedLanguageCode if available (preserves original translation language)
        let translationLangCode: String
        if let storedCode = note.translatedLanguageCode {
            translationLangCode = storedCode
        } else {
            // Fallback to calculating from current language configuration (for backward compatibility)
            let detectedLang = note.detectedLanguage ?? settings.languageConfiguration.sourceLanguageCode
            translationLangCode = settings.languageConfiguration.oppositeLanguageCode(for: detectedLang)
        }
        let translationLabel = LanguageHelper.languageName(for: translationLangCode)
        let allText = note.allTextForSharing(translationLabel: translationLabel)
        copyToClipboardWithMessage(allText, message: "All text copied")
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
    
    /// Speak text using AVSpeechSynthesizer with the appropriate language
    private func speakText(_ text: String, language: String) {
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
        // Use a state holder class to update the state
        stateHolder.onStateChange = { newValue in
            Task { @MainActor in
                isSpeaking = newValue
            }
        }
        let delegate = SpeechDelegate { [stateHolder] newValue in
            stateHolder.onStateChange?(newValue)
        }
        speechDelegate = delegate // Store to prevent deallocation
        synthesizer.delegate = delegate
        
        // Start speaking
        isSpeaking = true
        synthesizer.speak(utterance)
    }
    
    /// State holder class to bridge between delegate and SwiftUI state
    private class SpeakingStateHolder {
        var onStateChange: ((Bool) -> Void)?
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
    
    private var copyToastView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white)
            Text(copyToastMessage)
                .font(.subheadline)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.black)
        }
        .padding(.bottom, 16)
    }
}




