import SwiftUI
import SwiftData
import AVFoundation
import UIKit

struct NotesListView: View {
    @Environment(\.modelContext) private var modelContext
    // Optimized query: add animation parameter to prevent unnecessary re-renders
    @Query(
        sort: [SortDescriptor(\Transcription.timestamp, order: .forward)],
        animation: .default
    ) private var notes: [Transcription]

    @State private var showingNoModesAlert: Bool = false
    @State private var hasScrolledToBottom: Bool = false
    @State private var previousNoteStates: [UUID: (hasTranslation: Bool, status: TranscriptionStatus)] = [:]
    @State private var notesTranslationState: String = "" // Used to trigger onChange
    @State private var translationCheckTask: Task<Void, Never>? = nil
    @EnvironmentObject private var recordingManager: RecordingManager
    @StateObject private var settings = AppSettings.shared

    init() {}

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top section: Notes list
                content
                    .navigationTitle("Learn Spanish")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink(destination: SettingsView()) {
                                Image(systemName: "gearshape")
                                    .foregroundStyle(.primary)
                            }
                            .accessibilityLabel("Settings")
                            .accessibilityHint("Double tap to open app settings")
                        }
                    }
                
                // Bottom section: Fixed mic/recording controls
                fixedBottomSection
            }
                .alert(item: $recordingManager.activeRecordingAlert) { alertType in
                    switch alertType {
                    case .permissionDenied:
                        return Alert(
                            title: Text("Microphone Access Denied"),
                            message: Text("To record audio, please grant microphone access in Settings."),
                            primaryButton: .default(Text("Settings"), action: recordingManager.openSettings),
                            secondaryButton: .cancel()
                        )
                    case .busy:
                        return Alert(
                            title: Text("Microphone In Use"),
                            message: Text("Another app is using the microphone. Please try again."),
                            dismissButton: .default(Text("OK"))
                        )
                    case .generic(let error):
                        let nsError = error as NSError
                        if nsError.domain == NSOSStatusErrorDomain && nsError.code == 561017449 { // '!act' error
                             return Alert(
                                title: Text("Microphone In Use"),
                                message: Text("Another app is using the microphone. Please try again."),
                                dismissButton: .default(Text("OK"))
                            )
                        }
                        return Alert(
                            title: Text("Recording Failed"),
                            message: Text("Could not start recording: \(error.localizedDescription)"),
                            dismissButton: .default(Text("OK"))
                        )
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .stopRecordingFromKeyboard)) { _ in
                    Logger.debug("Received stopRecordingFromKeyboard notification", category: "NotesListView")
                    if recordingManager.isRecording {
                        Logger.debug("Stopping recording (from keyboard)", category: "NotesListView")
                        recordingManager.stopRecording(modelContext: modelContext, fromKeyboard: true)
                    } else {
                        Logger.warning("Stop notification received but not recording", category: "NotesListView")
                    }
                }
                .onAppear {
                    // Check for stop flag when view appears
                    let coordinator = AppGroupCoordinator.shared
                    if coordinator.checkAndConsumeStopRecordingFlag() {
                        Logger.debug("Found stop flag on appear, stopping recording", category: "NotesListView")
                        if recordingManager.isRecording {
                            NotificationCenter.default.post(name: .stopRecordingFromKeyboard, object: nil)
                        }
                    }
                }
        }
    }

    private var content: some View {
        Group {
            if notes.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    List {
                        Section {
                            ForEach(notes, id: \.id) { note in
                                NavigationLink(destination: NoteDetailView(note: note)) {
                                    NoteRowView(note: note)
                                        .id(note.id) // Stable identifier for SwiftUI diffing
                                }
                                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color(.secondarySystemGroupedBackground))
                                // Removed redundant .id() modifier - ForEach already handles identification
                                // Optimized animation to only trigger on note changes, not count changes
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                // Delete action
                                Button(role: .destructive) {
                                    withAnimation {
                                        deleteItem(note)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                
                                // Copy action
                                Button {
                                    copyNoteToClipboard(note)
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                .tint(.blue)
                            }
                        }
                        .onDelete(perform: deleteItems)
                    }
                }
                .listStyle(.insetGrouped)
                .contentMargins(.vertical, 0, for: .scrollContent)
                .refreshable {
                    // Pull-to-refresh functionality
                    await refreshNotes()
                }
                .padding(.bottom, 12)
                .onAppear {
                    scrollToBottom(proxy: proxy, isInitial: true)
                    updateNotesTranslationState()
                }
                .onChange(of: notes.count) { oldCount, newCount in
                    // Scroll to bottom when new notes are added
                    if newCount > oldCount {
                        scrollToBottom(proxy: proxy)
                    }
                    // Update translation state tracking
                    updateNotesTranslationState()
                }
                .onChange(of: recordingManager.isRecording) { wasRecording, isRecording in
                    // When recording stops, scroll to bottom to show the new note
                    if wasRecording && !isRecording {
                        scrollToBottom(proxy: proxy)
                        // Start periodic checking for translation completion
                        startTranslationCompletionCheck(proxy: proxy)
                    } else if isRecording {
                        // Cancel any ongoing check when recording starts
                        translationCheckTask?.cancel()
                        translationCheckTask = nil
                    }
                }
                .onChange(of: notesTranslationState) { _, _ in
                    checkAndScrollToCompletedTranslation(proxy: proxy)
                }
                // Watch for transcription status changes more directly
                .onChange(of: notes.map { "\($0.id.uuidString)-\($0.transcriptionStatus.rawValue)-\($0.translatedText != nil ? "1" : "0")" }.joined(separator: "|")) { _, _ in
                    // Update state when transcription status or translation changes
                    updateNotesTranslationState()
                }
                .onAppear {
                    updateNotesTranslationState()
                }
                }
            }
        }
    }

    
    @MainActor
    private func refreshNotes() async {
        // Small delay to show refresh animation
        try? await Task.sleep(nanoseconds: 500_000_000)
        // Force SwiftData to refresh
        modelContext.processPendingChanges()
    }
    
    /// Scroll to bottom of list (optimized - uses proper async timing)
    private func scrollToBottom(proxy: ScrollViewProxy, isInitial: Bool = false) {
        guard !notes.isEmpty else { return }
        
        // For initial scroll, mark as done
        if isInitial {
            guard !hasScrolledToBottom else { return }
            hasScrolledToBottom = true
        }
        
        // Use Task with a small delay to ensure SwiftData has updated the UI
        // This is more reliable than DispatchQueue.main.async which might run before UI updates
        Task { @MainActor in
            // Small delay to ensure SwiftData/UI has updated (but shorter than before)
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds instead of 0.3
            
            if let lastNote = self.notes.last {
                withAnimation {
                    proxy.scrollTo(lastNote.id, anchor: .bottom)
                }
            }
        }
    }
    
    /// Scroll to the top of a specific note so the complete note is visible from the beginning
    private func scrollToNoteTop(proxy: ScrollViewProxy, noteId: UUID) {
        Task { @MainActor in
            // Small delay to ensure SwiftData/UI has updated with the translation
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds to allow UI to update
            
            withAnimation(.easeInOut(duration: 0.5)) {
                proxy.scrollTo(noteId, anchor: .top)
            }
        }
    }
    
    /// Update the notes translation state string to trigger onChange
    private func updateNotesTranslationState() {
        let stateString = notes.map { note in
            "\(note.id.uuidString)-\(note.translatedText != nil ? "1" : "0")-\(note.transcriptionStatus.rawValue)"
        }.joined(separator: "|")
        notesTranslationState = stateString
    }
    
    /// Start periodic checking for translation completion after recording stops
    private func startTranslationCompletionCheck(proxy: ScrollViewProxy) {
        // Cancel any existing task
        translationCheckTask?.cancel()
        
        translationCheckTask = Task { @MainActor in
            // Check periodically for up to 30 seconds
            for _ in 0..<30 {
                // Check if we should scroll to completed translation
                let didScroll = checkAndScrollToCompletedTranslation(proxy: proxy)
                
                // If we scrolled, we're done - break early
                if didScroll {
                    break
                }
                
                // Wait 1 second before next check
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                // Break early if task was cancelled
                if Task.isCancelled {
                    break
                }
            }
        }
    }
    
    /// Check if any note just completed translation and scroll to it
    /// Returns true if scrolling was triggered
    @discardableResult
    private func checkAndScrollToCompletedTranslation(proxy: ScrollViewProxy) -> Bool {
        // Check if any note just completed translation
        var foundCompletedTranslation = false
        
        // Find the most recently added note (last in the array since sorted by timestamp forward)
        if let latestNote = notes.last {
            let noteId = latestNote.id
            let nowHasTranslation = latestNote.translatedText != nil && !(latestNote.translatedText?.isEmpty ?? true)
            let nowStatus = latestNote.transcriptionStatus
            
            // Get previous state
            let previousState = previousNoteStates[noteId]
            let previouslyHadTranslation = previousState?.hasTranslation ?? false
            let previousStatus = previousState?.status
            
            // If translation just completed (was nil/empty, now has value) and status is completed
            if !previouslyHadTranslation && nowHasTranslation && nowStatus == .completed {
                // Scroll to this note's top so user can see the complete note
                scrollToNoteTop(proxy: proxy, noteId: noteId)
                foundCompletedTranslation = true
            }
            
            // Also check if transcription just completed (status changed from pending to completed)
            // and translation is now available
            if previousStatus == .pending && nowStatus == .completed && nowHasTranslation {
                // If we haven't already scrolled, scroll to this note
                if !foundCompletedTranslation {
                    scrollToNoteTop(proxy: proxy, noteId: noteId)
                    foundCompletedTranslation = true
                }
            }
            
            // If status is completed and has translation, but we haven't scrolled yet (first time seeing it)
            if nowStatus == .completed && nowHasTranslation && previousState == nil {
                scrollToNoteTop(proxy: proxy, noteId: noteId)
                foundCompletedTranslation = true
            }
        }
        
        // Update previous states
        previousNoteStates = Dictionary(uniqueKeysWithValues: notes.map { note in
            (note.id, (note.translatedText != nil && !(note.translatedText?.isEmpty ?? true), note.transcriptionStatus))
        })
        
        // Update state string for next change detection (but only if we didn't just update it)
        // This prevents infinite loops
        let newStateString = notes.map { note in
            "\(note.id.uuidString)-\(note.translatedText != nil && !(note.translatedText?.isEmpty ?? true) ? "1" : "0")-\(note.transcriptionStatus.rawValue)"
        }.joined(separator: "|")
        
        if newStateString != notesTranslationState {
            notesTranslationState = newStateString
        }
        
        return foundCompletedTranslation
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("Start Learning")
                .font(.title2)
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Empty state. Start Learning.")
    }

    private var fixedBottomSection: some View {
        VStack(spacing: 0) {
            if recordingManager.isRecording {
                // Recording UI - expanded bottom section
                recordingBottomSection
            } else {
                // Mic button - compact bottom section
                micButtonSection
            }
        }
        .background(Color(.systemGroupedBackground))
        .alert("No Modes Found", isPresented: $showingNoModesAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please create a new mode in Settings before recording.")
        }
    }
    
    private var micButtonSection: some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: {
                handleRecordingButtonTap()
            }) {
                Label("Practice Spanish", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .accessibilityLabel("Start recording to practice Spanish")
        .accessibilityHint("Double tap to start recording")
    }
    
    private var recordingBottomSection: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 16) {
                // Timer
                Text(recordingManager.currentDuration.formattedTimeString)
                    .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Recording duration: \(recordingManager.currentDuration.formattedTimeString)")
                
                Spacer()
                
                // Stop Button
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    recordingManager.stopRecording(modelContext: modelContext)
                }) {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .accessibilityLabel("Recording in progress")
    }
    
    
    private func handleRecordingButtonTap() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        if AppSettings.shared.modes.isEmpty {
            showingNoModesAlert = true
        } else {
            recordingManager.startRecordingFlow()
        }
    }

    // MARK: - Helper Functions
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets { modelContext.delete(notes[index]) }
        }
    }
    
    private func deleteItem(_ note: Transcription) {
        withAnimation {
            modelContext.delete(note)
            modelContext.processPendingChanges()
            try? modelContext.save()
        }
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func copyNoteToClipboard(_ note: Transcription) {
        let detectedLang = note.detectedLanguage ?? "en"
        let translationLabel = detectedLang == "es" ? "English" : "Spanish"
        let allText = note.allTextForSharing(translationLabel: translationLabel)
        _ = copyToClipboard(allText)
    }
}

#Preview {
    NotesListView()
        .modelContainer(for: [Transcription.self])
        .environmentObject(RecordingManager())
}


