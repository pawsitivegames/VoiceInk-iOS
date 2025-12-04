import SwiftUI
import SwiftData
import AVFoundation
import UIKit

struct NotesListView: View {
    @Environment(\.modelContext) private var modelContext
    // OPTIMIZATION: Use .smooth animation for better performance, only animate when needed
    @Query(
        sort: [SortDescriptor(\Transcription.timestamp, order: .forward)],
        animation: .smooth
    ) private var notes: [Transcription]

    @State private var showingNoModesAlert: Bool = false
    @State private var isRetranslating: Bool = false
    @State private var lastLanguageConfig: LanguageConfiguration?
    @State private var lastNoteId: UUID?
    @State private var scrollTask: Task<Void, Never>?
    @EnvironmentObject private var recordingManager: RecordingManager
    @StateObject private var settings = AppSettings.shared
    @StateObject private var clipboardService = ClipboardService.shared
    
    // OPTIMIZATION: Cache computed properties to avoid recalculating on every body evaluation
    private var navigationTitle: String {
        // Access settings once per evaluation
        let targetCode = settings.targetLanguageCode
        let targetName = LanguageHelper.languageName(for: targetCode)
        return "Learn \(targetName)"
    }
    
    private var practiceButtonText: String {
        // Access settings once per evaluation
        let targetCode = settings.targetLanguageCode
        let targetName = LanguageHelper.languageName(for: targetCode)
        return "Practice \(targetName)"
    }

    init() {}

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top section: Notes list
                content
                    .navigationTitle(navigationTitle)
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
            .overlay(alignment: .top) {
                // Processing banner - positioned below navigation bar for better visibility
                if recordingManager.recordingState == .processing {
                    VStack(spacing: 0) {
                        // Position below navigation bar (accounts for large title + safe area)
                        Spacer()
                            .frame(height: 120)
                        
                        ProcessingView(
                            isPresented: .constant(true),
                            message: "Processing transcription and translation..."
                        )
                        
                        Spacer()
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: recordingManager.recordingState)
                } else if isRetranslating {
                    VStack(spacing: 0) {
                        // Position below navigation bar (accounts for large title + safe area)
                        Spacer()
                            .frame(height: 120)
                        
                        ProcessingView(
                            isPresented: .constant(true),
                            message: "Retranslating all notes..."
                        )
                        
                        Spacer()
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: isRetranslating)
                }
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
                // Note: No longer need translationCompleted notification handler
                // SwiftData's @Query automatically updates when note is inserted
                .onAppear {
                    // Check for stop flag when view appears
                    let coordinator = AppGroupCoordinator.shared
                    if coordinator.checkAndConsumeStopRecordingFlag() {
                        Logger.debug("Found stop flag on appear, stopping recording", category: "NotesListView")
                        if recordingManager.isRecording {
                            NotificationCenter.default.post(name: .stopRecordingFromKeyboard, object: nil)
                        }
                    }
                    
                    // Store initial language configuration
                    lastLanguageConfig = settings.languageConfiguration
                }
                .onChange(of: settings.languageConfiguration) { oldValue, newValue in
                    // OPTIMIZATION: Only retranslate if language configuration actually changed
                    // Compare with last known config to avoid unnecessary retranslations
                    guard let lastConfig = lastLanguageConfig else {
                        // First load - just store the config, don't retranslate
                        lastLanguageConfig = newValue
                        return
                    }
                    
                    let sourceChanged = lastConfig.sourceLanguageCode != newValue.sourceLanguageCode
                    let targetChanged = lastConfig.targetLanguageCode != newValue.targetLanguageCode
                    
                    if sourceChanged || targetChanged {
                        Logger.info("Language configuration changed (source: \(sourceChanged), target: \(targetChanged)), retranslating all notes", category: "NotesListView")
                        retranslateAllNotes()
                    }
                    
                    // Always update lastLanguageConfig to track current state
                    lastLanguageConfig = newValue
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
                            // OPTIMIZATION: ForEach with explicit id is already efficient
                            // The .id() modifier on NoteRowView is redundant but harmless
                            ForEach(notes, id: \.id) { note in
                                NavigationLink(destination: NoteDetailView(note: note)) {
                                    NoteRowView(note: note)
                                }
                                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color(.secondarySystemGroupedBackground))
                                // OPTIMIZATION: Only animate insertions, not all updates
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
                    .onChange(of: notes.count) { oldCount, newCount in
                        // Only scroll when count increases (new note added after translation completes)
                        // Notes are only inserted into SwiftData after translation is done
                        if newCount > oldCount, let newNote = notes.last, newNote.id != lastNoteId, !isRetranslating {
                            lastNoteId = newNote.id
                            
                            // Cancel any pending scroll task to avoid multiple scrolls
                            scrollTask?.cancel()
                            
                            // Scroll to show the new note at the top of the list
                            scrollTask = Task { @MainActor in
                                // Scroll to the top of the note so the complete note is visible
                                scrollToNoteTop(proxy: proxy, noteId: newNote.id)
                            }
                        } else if newCount < oldCount {
                            // Reset lastNoteId on deletion to allow scrolling to new notes
                            lastNoteId = notes.last?.id
                        }
                    }
                }
            }
        }
    }

    
    @MainActor
    private func refreshNotes() async {
        // Small delay to show refresh animation
        try? await Task.sleep(nanoseconds: 500_000_000)
        // OPTIMIZATION: processPendingChanges is sufficient - SwiftData's @Query automatically
        // updates the view when data changes, so no manual refresh needed
        modelContext.processPendingChanges()
    }
    
    /// Scroll to the top of a specific note so the complete note is visible from the beginning
    /// This ensures the user can see the whole note when it's added after translation completes
    private func scrollToNoteTop(proxy: ScrollViewProxy, noteId: UUID) {
        Task { @MainActor in
            // Small delay to ensure SwiftData/UI has updated with the translation
            // Notes are only inserted after translation completes, so this delay ensures
            // the view has fully rendered the complete note
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds to allow UI to update
            
            // Scroll to show the note's top at the top of the visible area
            // This ensures the user sees the complete note from the beginning
            withAnimation(.easeInOut(duration: 0.5)) {
                proxy.scrollTo(noteId, anchor: .top)
            }
        }
    }

    private var emptyStateText: String {
        let targetName = LanguageHelper.languageName(for: settings.targetLanguageCode)
        return "Start Learning \(targetName)"
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text(emptyStateText)
                .font(.title2)
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Empty state. \(emptyStateText).")
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
                Label(practiceButtonText, systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .accessibilityLabel("Start recording to \(practiceButtonText.lowercased())")
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
            // OPTIMIZATION: SwiftData automatically updates @Query on delete
            // Only need to save, processPendingChanges happens automatically
            try? modelContext.save()
        }
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func copyNoteToClipboard(_ note: Transcription) {
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
        clipboardService.copy(allText, message: "Note copied")
    }
    
    /// Retranslates all existing notes when language configuration changes
    @MainActor
    private func retranslateAllNotes() {
        guard !isRetranslating else {
            Logger.debug("Retranslation already in progress, skipping", category: "NotesListView")
            return
        }
        
        isRetranslating = true
        
        Task { @MainActor in
            defer { 
                isRetranslating = false
            }
            
            await TranscriptionRetryService.shared.retranslateAllNotes(modelContext: modelContext)
            
            // Process and save all changes in one batch
            modelContext.processPendingChanges()
            try? modelContext.save()
            
            // No need to force UI refresh - SwiftData's @Query will automatically update
            // when the underlying Transcription models are modified
            Logger.info("All notes retranslated with new language configuration", category: "NotesListView")
        }
    }
}

#Preview {
    NotesListView()
        .modelContainer(for: [Transcription.self])
        .environmentObject(RecordingManager())
}


