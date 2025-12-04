import SwiftUI
import UIKit

struct NoteRowView: View {
    let note: Transcription
    // Callbacks removed since star/share are gone
    let onToggleStar: () -> Void = {}
    let onToggleShare: () -> Void = {}
    
    @StateObject private var speechService = SpeechSynthesisService.shared
    @StateObject private var clipboardService = ClipboardService.shared
    @StateObject private var settings = AppSettings.shared
    
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
    
    // Helper functions to get language info - now take cached values as parameters
    private func languageInfo(for detectedLang: String?) -> (flag: String, label: String) {
        if let detectedLang = detectedLang {
            let langCode = detectedLang
            return (LanguageHelper.flag(for: langCode), LanguageHelper.languageName(for: langCode))
        }
        // Default to source language
        let sourceCode = settings.sourceLanguageCode
        return (LanguageHelper.flag(for: sourceCode), LanguageHelper.languageName(for: sourceCode))
    }
    
    private func translationInfo(for detectedLang: String?, translatedLanguageCode: String?) -> (flag: String, label: String) {
        // Use stored translatedLanguageCode if available (preserves original translation language)
        if let storedCode = translatedLanguageCode {
            return (LanguageHelper.flag(for: storedCode), LanguageHelper.languageName(for: storedCode))
        }
        // Fallback to calculating from current language configuration (for backward compatibility)
        if let detectedLang = detectedLang {
            let oppositeCode = settings.oppositeLanguageCode(for: detectedLang)
            return (LanguageHelper.flag(for: oppositeCode), LanguageHelper.languageName(for: oppositeCode))
        }
        // Default translation to target language
        let targetCode = settings.targetLanguageCode
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
                            let detectedLang = detectedLanguage ?? settings.sourceLanguageCode
                            speechService.speak(transcriptText, language: LanguageHelper.localeCode(for: detectedLang))
                        }) {
                            Text(languageInfo.flag)
                                .font(.title3)
                                .opacity(speechService.isSpeaking ? 0.6 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(languageInfo.label) flag")
                        .accessibilityHint("Double tap to hear \(languageInfo.label) pronunciation")
                        
                        // Text button - tappable to copy
                        Button(action: {
                            let englishText = enhancedText ?? noteText
                            clipboardService.copy(englishText, message: "\(languageInfo.label) copied")
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
                                let detectedLang = detectedLanguage ?? settings.sourceLanguageCode
                                return settings.oppositeLanguageCode(for: detectedLang)
                            }()
                            speechService.speak(translatedText, language: LanguageHelper.localeCode(for: targetCode))
                        }) {
                            Text(translationInfo.flag)
                                .font(.title3)
                                .opacity(speechService.isSpeaking ? 0.6 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(translationInfo.label) flag")
                        .accessibilityHint("Double tap to hear \(translationInfo.label) pronunciation")
                        
                        // Text button - tappable to copy
                        Button(action: {
                            clipboardService.copy(translatedText, message: "\(translationInfo.label) copied")
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
        .toast(clipboardService: clipboardService)
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
    

    private func copyAllText() {
        // Use stored translatedLanguageCode if available (preserves original translation language)
        let translationLangCode: String
        if let storedCode = note.translatedLanguageCode {
            translationLangCode = storedCode
        } else {
            // Fallback to calculating from current language configuration (for backward compatibility)
            let detectedLang = note.detectedLanguage ?? settings.sourceLanguageCode
            translationLangCode = settings.oppositeLanguageCode(for: detectedLang)
        }
        let translationLabel = LanguageHelper.languageName(for: translationLangCode)
        let allText = note.allTextForSharing(translationLabel: translationLabel)
        clipboardService.copy(allText, message: "All text copied")
    }
}




