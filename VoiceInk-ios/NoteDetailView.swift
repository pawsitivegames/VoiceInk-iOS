import SwiftUI
import SwiftData

struct NoteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var note: Transcription
    
    @State private var isRetranscribing = false
    @StateObject private var settings = AppSettings.shared
    @State private var showCopyToast = false
    @State private var copyToastMessage = ""
    @State private var showShareSheet = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Main content with scroll
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Transcription status and retry button
                        if note.needsTranscription {
                            transcriptionStatusView
                        }

                        // Transcript content
                        if note.transcriptionStatus == .completed {
                            transcriptContentView
                        }
                        
                        // Add bottom padding to account for audio player
                        if hasAudioFile {
                            Color.clear
                                .frame(height: 100)
                        }
                    }
                    .padding()
                }
                .scrollIndicators(.hidden)
                
                // Bottom audio player (web-form style)
                if hasAudioFile {
                    bottomAudioPlayer
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal)
                        .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 0 : 16)
                }
            }
        }
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    // Copy All (English + Spanish)
                    Button(action: { copyAllText() }) {
                        Label("Copy All", systemImage: "doc.on.doc.fill")
                    }
                    
                    Divider()
                    
                    // Share
                    Button(action: { showShareSheet = true }) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.blue)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [allTextForSharing])
        }
        .overlay(alignment: .bottom) {
            if showCopyToast {
                copyToastView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showCopyToast)
            }
        }
    }
    
    private var transcriptContentView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Side-by-side layout for both languages
            if let translatedText = note.translatedText, !translatedText.isEmpty, note.transcriptionStatus == .completed {
                // Both languages available - show side-by-side
                HStack(alignment: .top, spacing: 16) {
                    // Primary Language (detected)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(primaryLanguageLabel)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Button(action: { copyToClipboardWithMessage(displayedTranscriptText, message: "\(primaryLanguageLabel) text copied") }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                        
                        Text(displayedTranscriptText)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Translation Language
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(translationLanguageLabel)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Button(action: { copyToClipboardWithMessage(translatedText, message: "\(translationLanguageLabel) text copied") }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                        
                        Text(translatedText)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                // Only primary language available (or translation pending)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(primaryLanguageLabel)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Button(action: { copyToClipboardWithMessage(displayedTranscriptText, message: "\(primaryLanguageLabel) text copied") }) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                    
                    Text(displayedTranscriptText)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    
                    if note.transcriptionStatus == .completed && note.translatedText == nil {
                        // Translation pending indicator
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                                .id("translation-pending-\(note.id)") // Stable ID to help SwiftUI optimize rendering
                            Text("Translation pending...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .drawingGroup() // Isolate rendering to prevent flattening issues
                    }
                }
            }
            
            // Copy All Button - key functionality, one tap to copy everything
            Button(action: { copyAllText() }) {
                HStack {
                    Image(systemName: "doc.on.doc.fill")
                    Text("Copy All Text")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.regular)
        }
    }
    
    private var displayedTranscriptText: String {
        return note.displayText
    }
    
    /// Get the primary language label based on detected language
    private var primaryLanguageLabel: String {
        if note.detectedLanguage == "es" {
            return "Spanish"
        } else {
            return "English"
        }
    }
    
    /// Get the translation language label based on detected language
    private var translationLanguageLabel: String {
        if note.detectedLanguage == "es" {
            return "English"
        } else {
            return "Spanish"
        }
    }
    
    /// Get the primary language flag emoji
    private var primaryLanguageFlag: String {
        if note.detectedLanguage == "es" {
            return "🇪🇸"
        } else {
            return "🇺🇸"
        }
    }
    
    /// Get the translation language flag emoji
    private var translationLanguageFlag: String {
        if note.detectedLanguage == "es" {
            return "🇺🇸"
        } else {
            return "🇪🇸"
        }
    }
    
    // Lazy evaluation - only check file existence when needed
    private var hasAudioFile: Bool {
        guard let audioPath = note.fullAudioPath else { return false }
        return FileManager.default.fileExists(atPath: audioPath)
    }

    // Summary card removed per design feedback
    
    private var bottomAudioPlayer: some View {
        VStack(spacing: 0) {
            if let audioPath = note.fullAudioPath,
               FileManager.default.fileExists(atPath: audioPath) {
                AudioPlayerView(audioFilePath: audioPath, duration: note.duration, timestamp: note.timestamp)
            } else if note.audioFileURL != nil && !note.audioFileURL!.isEmpty {
                // Modern error state - file missing
                HStack(spacing: 12) {
                    Circle()
                        .fill(.orange.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "exclamationmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.orange)
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audio Unavailable")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("File not found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            } else if note.duration > 0 {
                // Modern error state - path missing
                HStack(spacing: 12) {
                    Circle()
                        .fill(.orange.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "exclamationmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.orange)
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audio Unavailable")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("Path missing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
    }
    
    
    private var relativeTimestamp: String {
        return note.timestamp.relativeTimeString
    }
    
    private var transcriptionStatusView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: note.transcriptionStatus == .failed ? "exclamationmark.triangle.fill" : "clock.fill")
                    .foregroundStyle(note.transcriptionStatus == .failed ? .red : .orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.transcriptionStatus == .failed ? "Transcription Failed" : "Transcription Pending")
                        .font(.subheadline.weight(.medium))
                    if let error = note.transcriptionError, !error.isEmpty {
                        Text(error)
                            .font(.caption)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                Spacer()
            }
            
            if isRetranscribing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                        .id("retranscribing-\(note.id)") // Stable ID to help SwiftUI optimize rendering
                    Text("Retranscribing...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .drawingGroup() // Isolate rendering to prevent flattening issues
            } else {
                Button {
                    retranscribe()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.regular)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func retranscribe() {
        isRetranscribing = true
        
        Task {
            defer { isRetranscribing = false }
            
            do {
                _ = try await TranscriptionRetryService.shared.retranscribe(note: note)
                modelContext.processPendingChanges()
                try? modelContext.save() // Save the updated note
            } catch {
                // Error handling is already done in the service
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
        let allText = note.allTextForSharing(translationLabel: translationLanguageLabel)
        copyToClipboardWithMessage(allText, message: "All text copied")
    }
    
    private var allTextForSharing: String {
        return note.allTextForSharing(translationLabel: translationLanguageLabel)
    }
    
    private var copyToastView: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white)
            Text(copyToastMessage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.black.opacity(0.85))
        }
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 20)
        .padding(.bottom, 100)
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


