import SwiftUI
import UIKit

struct NoteRowView: View {
    let note: Transcription
    // Callbacks removed since star/share are gone
    let onToggleStar: () -> Void = {}
    let onToggleShare: () -> Void = {}
    
    @State private var showCopyToast = false
    @State private var copyToastMessage = ""
    
    // Cache expensive computed properties (performance optimization)
    private var cachedTranscriptText: String {
        switch note.transcriptionStatus {
        case .pending:
            return "Processing translation..."
        case .failed:
            return "Transcription failed - tap to retry"
        case .completed:
            // Prioritize enhanced text (post-processed result) over original text
            if let enhancedText = note.enhancedText, !enhancedText.isEmpty {
                return enhancedText
            } else if !note.text.isEmpty {
                return note.text
            } else {
                return "No audible content detected."
            }
        }
    }
    
    private var cachedLanguageInfo: (flag: String, label: String) {
        if let detectedLang = note.detectedLanguage {
            return detectedLang == "es" ? ("🇪🇸", "Spanish") : ("🇺🇸", "English")
        }
        return ("🇺🇸", "English") // Default to English
    }
    
    private var cachedTranslationInfo: (flag: String, label: String) {
        if let detectedLang = note.detectedLanguage {
            return detectedLang == "es" ? ("🇺🇸", "English") : ("🇪🇸", "Spanish")
        }
        return ("🇪🇸", "Spanish") // Default translation to Spanish
    }
    
    private var cachedRelativeTimestamp: String {
        return note.timestamp.relativeTimeString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main content area
            VStack(alignment: .leading, spacing: 0) {
                // Original language (detected) - tappable to copy
                if note.transcriptionStatus == .completed {
                    Button(action: {
                        let englishText = note.enhancedText ?? note.text
                        copyToClipboardWithMessage(englishText, message: "\(cachedLanguageInfo.label) copied")
                    }) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(cachedLanguageInfo.flag)
                                .font(.title3)
                            
                            Text(cachedTranscriptText)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(cachedLanguageInfo.label) text: \(cachedTranscriptText)")
                    .accessibilityHint("Double tap to copy \(cachedLanguageInfo.label) text")
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        Text(cachedLanguageInfo.flag)
                            .font(.title3)
                        
                        Text(cachedTranscriptText)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Translation (opposite language) - tappable to copy
                if let translatedText = note.translatedText, !translatedText.isEmpty, note.transcriptionStatus == .completed {
                    Divider()
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                    
                    Button(action: {
                        copyToClipboardWithMessage(translatedText, message: "\(cachedTranslationInfo.label) copied")
                    }) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(cachedTranslationInfo.flag)
                                .font(.title3)
                            
                            Text(translatedText)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(cachedTranslationInfo.label) translation: \(translatedText)")
                    .accessibilityHint("Double tap to copy \(cachedTranslationInfo.label) translation")
                    
                    // Copy Both button - key functionality, one tap to copy everything
                    Button(action: {
                        copyAllText()
                    }) {
                        Label("Copy Both", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .padding(.top, 12)
                }
            }

            // Footer metadata
            HStack(spacing: 8) {
                if note.duration > 0 {
                    Text("\(cachedRelativeTimestamp) • \(note.duration.formattedTimeString)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(cachedRelativeTimestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if note.transcriptionStatus == .pending {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.8)
                            .id("processing-\(note.id)") // Stable ID to help SwiftUI optimize rendering
                        Text("Processing")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Processing transcription")
                    .drawingGroup() // Isolate rendering to prevent flattening issues
                } else if note.transcriptionStatus == .failed {
                    Label("Failed", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Transcription failed")
                }
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .drawingGroup() // Optimize rendering for complex row content
        .overlay(alignment: .bottom) {
            if showCopyToast {
                copyToastView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.default, value: showCopyToast)
            }
        }
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
        let detectedLang = note.detectedLanguage ?? "en"
        let translationLabel = detectedLang == "es" ? "English" : "Spanish"
        let allText = note.allTextForSharing(translationLabel: translationLabel)
        copyToClipboardWithMessage(allText, message: "All text copied")
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



