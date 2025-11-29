import SwiftUI
import SwiftData
import AVFoundation
import Combine
import UIKit

extension Notification.Name {
    static let stopRecordingFromKeyboard = Notification.Name("stopRecordingFromKeyboard")
    static let recordingStarted = Notification.Name("recordingStarted")
}

enum RecordingState: Equatable {
    case idle
    case recording
    case processing
    case completed(String)
    case error(String)
}

private enum MicrophonePermissionStatus {
    case granted, denied, undetermined
}

enum ActiveRecordingAlert: Identifiable {
    case permissionDenied
    case busy
    case generic(Error)
    
    var id: String {
        switch self {
        case .permissionDenied: return "permissionDenied"
        case .busy: return "busy"
        case .generic(let error): return "generic-\(error.localizedDescription)"
        }
    }
}
 
@MainActor
final class RecordingManager: ObservableObject {
    @Published var recordingState: RecordingState = .idle
    @Published var animate = false
    @Published var isRecordingSheetPresented = false
    @Published var activeRecordingAlert: ActiveRecordingAlert?
    @Published var currentRecordingNote: Transcription?
    @Published var currentDuration: Double = 0
    
    private let recorder = AudioRecorder()
    private let postProcessor = LLMPostProcessor()
    private let translationService = TranslationService()
    private let settings = AppSettings.shared
    private var durationTimer: Timer?
    
    // Serial queue for atomic state transitions to prevent race conditions
    private let stateQueue = DispatchQueue(label: "com.pawsitivegames.VoiceInk.RecordingManager.state", qos: .userInitiated)
    private var _isStartingRecording = false // Internal flag to prevent concurrent starts

    private let sessionManager = AudioSessionManager.shared
    private let coordinator = AppGroupCoordinator.shared
    // Thread-safe flag to track if recording was stopped from keyboard
    private var wasStoppedFromKeyboard = false {
        didSet {
            // Ensure coordinator state stays in sync
            if !wasStoppedFromKeyboard && oldValue {
                // Flag was reset, ensure coordinator state is updated if needed
                coordinator.updateRecordingState(isRecording)
            }
        }
    }
    
    // Optimized LRU cache for language detection using NSCache (automatic memory management)
    private let languageDetectionCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 200 // Limit number of entries
        cache.totalCostLimit = 1024 * 1024 // 1MB limit for memory safety
        return cache
    }()
    
    // PERFORMANCE: Pre-compiled regex patterns for text cleaning (compiled once, reused many times)
    private static let doubleNewlineRegex = try! NSRegularExpression(pattern: "\n\n+", options: [])
    private static let whitespaceRegex = try! NSRegularExpression(pattern: "[ \t]+", options: [])
    
    var isRecording: Bool {
        recordingState == .recording
    }
    
    // MARK: - Initialization
    init() {
        Logger.debug("RecordingManager initialized", category: "RecordingManager")
        setupCoordinatorCallbacks()
        setupPermissionObserver()
    }
    
    deinit {
        durationTimer?.invalidate()
    }
    
    // MARK: - Coordinator Setup
    private func setupCoordinatorCallbacks() {
        // Simplified: Since app is always in foreground when opened via URL scheme,
        // we can directly start recording without complex state checking
        coordinator.onStartRecordingRequested = { [weak self] in
            guard let self = self else { return }
            Logger.debug("Start recording requested (app is in foreground)", category: "RecordingManager")
            
            // Only start if not already recording
            guard !self.isRecording else {
                Logger.warning("Already recording, ignoring duplicate request", category: "RecordingManager")
                return
            }
            
            // Start recording flow directly
            self.startRecordingFlow()
        }
        
        coordinator.onStopRecordingRequested = { [weak self] in
            guard let self = self else {
                Logger.warning("Stop callback: self is nil", category: "RecordingManager")
                return
            }
            Logger.debug("Stop recording requested from keyboard extension (via callback)", category: "RecordingManager")
            // Defer coordinator property access to avoid early UserDefaults access
            let isActivated = self.coordinator.isActivated
            Logger.debug("Current state - isRecording: \(self.isRecording), isActivated: \(isActivated)", category: "RecordingManager")
            guard self.isRecording else {
                Logger.warning("Stop requested but not currently recording - ignoring", category: "RecordingManager")
                return
            }
            // Atomically mark that this was stopped from keyboard
            self.stateQueue.sync {
                self.wasStoppedFromKeyboard = true
            }
            Logger.debug("Marked as stopped from keyboard, posting notification", category: "RecordingManager")
            // We need modelContext, so we'll handle this via a notification instead
            // Post on main thread to ensure it's processed
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .stopRecordingFromKeyboard, object: nil)
            }
        }
        
        coordinator.onActivationRequested = { [weak self] in
            guard let self = self else { return }
            Logger.debug("Activation requested (app is in foreground)", category: "RecordingManager")
            self.handleActivationRequest()
        }
        
        Logger.debug("Coordinator callbacks set up", category: "RecordingManager")
    }
    
    // MARK: - Activation Flow
    
    private func handleActivationRequest() {
        Logger.debug("handleActivationRequest() called", category: "RecordingManager")
        
        // Check permissions first
        let permissionStatus = checkPermissionStatus()
        Logger.debug("Permission status: \(permissionStatus)", category: "RecordingManager")
        
        switch permissionStatus {
        case .granted:
            // Permissions already granted, just activate session
            Logger.debug("Permissions already granted, activating session", category: "RecordingManager")
            activateSessionForKeyboard()
        case .denied:
            // Permissions denied
            Logger.warning("Permissions denied, showing alert", category: "RecordingManager")
            activeRecordingAlert = .permissionDenied
            coordinator.updateActivationState(false)
        case .undetermined:
            // Request permissions (app is in foreground when opened via URL)
            Logger.debug("Permissions undetermined, requesting permission", category: "RecordingManager")
            requestPermission { [weak self] granted in
                Logger.debug("Permission request completed, granted: \(granted)", category: "RecordingManager")
                if granted {
                    Logger.debug("Permission granted, activating session", category: "RecordingManager")
                    self?.activateSessionForKeyboard()
                } else {
                    Logger.warning("Permission denied by user", category: "RecordingManager")
                    self?.activeRecordingAlert = .permissionDenied
                    self?.coordinator.updateActivationState(false)
                }
            }
        }
    }
    
    private func activateSessionForKeyboard() {
        Logger.debug("activateSessionForKeyboard() called", category: "RecordingManager")
        
        Task {
            do {
                // Activate audio session with 10-minute timeout for keyboard mode
                Logger.debug("Activating audio session", category: "RecordingManager")
                try await sessionManager.activateSessionForRecording()
                Logger.info("Audio session activated successfully", category: "RecordingManager")
                
                // Set timeout to 10 minutes (600 seconds) for keyboard mode
                // Temporarily override the setting
                let originalTimeout = settings.audioSessionTimeoutSeconds
                settings.audioSessionTimeoutSeconds = 600
                
                // Schedule deactivation after 10 minutes
                sessionManager.scheduleDeactivation()
                
                // Restore original timeout setting
                settings.audioSessionTimeoutSeconds = originalTimeout
                
                // Update coordinator state
                coordinator.updateActivationState(true)
                
                // Show persistent notification to keep app active in background
                NotificationManager.shared.showActiveSessionNotification()
                
                Logger.info("Audio session activated for keyboard mode (10-minute window)", category: "RecordingManager")
            } catch {
                Logger.error("Failed to activate session for keyboard: \(error.localizedDescription)", category: "RecordingManager")
                coordinator.updateActivationState(false)
                activeRecordingAlert = .generic(error)
            }
        }
    }
    
    // MARK: - Recording Flow (Simplified)
    

    
    // MARK: - Recording Flow
    func startRecordingFlow() {
        Logger.debug("startRecordingFlow() called", category: "RecordingManager")
        
        // Atomic check and set to prevent race conditions
        var shouldProceed = false
        stateQueue.sync {
            guard !isRecording && !_isStartingRecording else {
                Logger.warning("Already recording or starting, ignoring duplicate startRecordingFlow() call", category: "RecordingManager")
                return
            }
            _isStartingRecording = true
            shouldProceed = true
        }
        
        guard shouldProceed else { return }
        
        // Check app state - must be in foreground
        let appState = UIApplication.shared.applicationState
        guard appState == .active else {
            stateQueue.sync { _isStartingRecording = false }
            Logger.error("App is not in foreground (state: \(appState.rawValue)), cannot start recording", category: "RecordingManager")
            activeRecordingAlert = .generic(NSError(domain: "com.pawsitivegames.VoiceInk.RecordingManager", code: 1007, userInfo: [NSLocalizedDescriptionKey: "App must be in foreground to start recording"]))
            return
        }
        
        let permissionStatus = checkPermissionStatus()
        Logger.debug("Permission status: \(permissionStatus), Audio session active: \(sessionManager.isSessionActive), Coordinator isActivated: \(coordinator.isActivated)", category: "RecordingManager")
        
        switch permissionStatus {
        case .granted:
            Logger.debug("Permissions granted, updating UI immediately", category: "RecordingManager")
            // Update UI state immediately for instant feedback
            stateQueue.sync {
                _isStartingRecording = false
            }
            recordingState = .recording
            animate = true
            coordinator.updateRecordingState(true)
            // Continue with async setup in background
            Task { await proceedToStartRecording() }
        case .denied:
            stateQueue.sync { _isStartingRecording = false }
            Logger.warning("Permissions denied, showing alert", category: "RecordingManager")
            activeRecordingAlert = .permissionDenied
        case .undetermined:
            Logger.debug("Permissions undetermined, requesting permission", category: "RecordingManager")
            requestPermission { [weak self] granted in
                Logger.debug("Permission request completed, granted: \(granted)", category: "RecordingManager")
                if granted {
                    // Update UI state immediately
                    self?.stateQueue.sync { self?._isStartingRecording = false }
                    self?.recordingState = .recording
                    self?.animate = true
                    self?.coordinator.updateRecordingState(true)
                    // Continue with async setup in background
                    Task { @MainActor in
                        await self?.proceedToStartRecording()
                    }
                } else {
                    self?.stateQueue.sync { self?._isStartingRecording = false }
                    Logger.warning("Permission denied by user", category: "RecordingManager")
                    self?.activeRecordingAlert = .permissionDenied
                }
            }
        }
    }
    
    private func proceedToStartRecording() async {
        Logger.debug("proceedToStartRecording() called", category: "RecordingManager")
        
        // Verify app is still in foreground
        let appState = UIApplication.shared.applicationState
        guard appState == .active else {
            Logger.error("App is not in foreground (state: \(appState.rawValue)), cannot proceed", category: "RecordingManager")
            activeRecordingAlert = .generic(NSError(domain: "com.pawsitivegames.VoiceInk.RecordingManager", code: 1008, userInfo: [NSLocalizedDescriptionKey: "App must be in foreground to start recording"]))
            recordingState = .idle
            coordinator.updateRecordingState(false)
            return
        }
        
        // Verify audio session is active before starting
        if !sessionManager.isSessionActive {
            Logger.warning("Audio session is not active, attempting to activate", category: "RecordingManager")
            do {
                try await sessionManager.activateSessionForRecording()
                Logger.info("Audio session activated successfully", category: "RecordingManager")
            } catch {
                Logger.error("Failed to activate audio session: \(error.localizedDescription)", category: "RecordingManager")
                activeRecordingAlert = .generic(error)
                recordingState = .idle
                coordinator.updateRecordingState(false)
                return
            }
        }
        
        // Cache keyboard mode state to prevent race conditions from state changes
        let isKeyboardMode = coordinator.isActivated
        
        // If session is already activated (keyboard mode), extend the timeout
        if isKeyboardMode {
            Logger.debug("Keyboard mode detected, extending audio session timeout", category: "RecordingManager")
            sessionManager.extendTimeout()
        }
        
        // Auto-select first mode if none is selected
        if settings.selectedModeId == nil && !settings.modes.isEmpty {
            settings.selectedModeId = settings.modes.first?.id
            Logger.debug("Auto-selected first mode: \(settings.modes.first?.name ?? "unknown")", category: "RecordingManager")
        }
        
        Logger.debug("Starting audio recorder", category: "RecordingManager")
        
        Task { @MainActor in
            do {
                try await recorder.startRecording()
                Logger.info("Audio recorder started successfully", category: "RecordingManager")
                
                startDurationTimer()
                
                // Verify recording actually started
                guard recorder.isRecording else {
                    throw NSError(domain: "com.pawsitivegames.VoiceInk.RecordingManager", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Recording failed to start - AVAudioRecorder.record() returned false"])
                }
                
                // Post notification that recording has started
                NotificationCenter.default.post(name: .recordingStarted, object: nil)
            } catch {
                Logger.error("Recording failed to start: \(error.localizedDescription)", category: "RecordingManager")
                
                // Ensure starting flag is cleared on error
                stateQueue.sync { _isStartingRecording = false }
                
                // Batch related state updates
                withAnimation {
                    activeRecordingAlert = .generic(error)
                    recordingState = .idle
                    animate = false
                }
                coordinator.updateRecordingState(false)
            }
        }
    }
    
    func stopRecording(modelContext: ModelContext, fromKeyboard: Bool = false) {
        Logger.debug("stopRecording() called, fromKeyboard: \(fromKeyboard)", category: "RecordingManager")
        
        // Atomically set flag and check state to prevent race conditions
        let shouldStoreTranscript = stateQueue.sync { () -> Bool in
            // Set flag if stopped from keyboard
            if fromKeyboard {
                wasStoppedFromKeyboard = true
            }
            // Capture flag value before any potential reset
            return wasStoppedFromKeyboard
        }
        
        // Stop recording and get file info
        recorder.stopRecording()
        stopDurationTimer()
        
        guard let fileURL = recorder.currentRecordingURL else {
            Logger.warning("No recording file URL available", category: "RecordingManager")
            // Reset flag if we couldn't stop properly
            stateQueue.sync { wasStoppedFromKeyboard = false }
            return
        }
        
        // Store relative path and duration
        let audioFileName = fileURL.lastPathComponent
        let recordingDuration = currentDuration
        
        // If stopped from keyboard, clear any old transcript first
        if shouldStoreTranscript {
            coordinator.clearOldTranscript()
        }
        
        // IMMEDIATELY create and insert the note with pending status
        let note = Transcription(
            text: "",
            duration: recordingDuration,
            audioFileURL: audioFileName,
            transcriptionStatus: .pending
        )
        modelContext.insert(note)
        modelContext.processPendingChanges()
        try? modelContext.save()
        
        // Atomically update all related state to keep everything in sync
        stateQueue.sync {
            // Reset the flag after checking
            wasStoppedFromKeyboard = false
        }
        
        // Reset UI state immediately so user can continue using the app
        // Batch related state updates to reduce view re-renders
        withAnimation {
            recordingState = .idle
            animate = false
            currentRecordingNote = note
            isRecordingSheetPresented = false
        }
        
        // Update coordinator state (must be after local state update)
        coordinator.updateRecordingState(false)
        
        // Note: We don't deactivate the session here if it's in keyboard mode
        // The session will stay active for the 10-minute window
        // The timeout will be extended on the next recording start
        
        // Start background transcription
        transcribeInBackground(note: note, audioFileName: audioFileName, recordingDuration: recordingDuration, modelContext: modelContext, shouldStoreTranscript: shouldStoreTranscript)
    }
    
    func cancelRecording() {
        recorder.discard()
        stopDurationTimer()
        
        // Atomically reset flag and update state
        stateQueue.sync {
            wasStoppedFromKeyboard = false
        }
        
        // Batch related state updates to reduce view re-renders
        withAnimation {
            recordingState = .idle
            animate = false
            isRecordingSheetPresented = false
        }
        currentDuration = 0
        
        // Update coordinator state (must be after local state update)
        coordinator.updateRecordingState(false)
    }
    
    // MARK: - Permissions
    private func checkPermissionStatus() -> MicrophonePermissionStatus {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        case .undetermined: return .undetermined
        @unknown default: return .undetermined
        }
    }
    
    /// Setup observer for microphone permission changes
    /// This handles the case where permission is revoked while the app is running
    private func setupPermissionObserver() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            // Check if permission was revoked
            let currentStatus = self.checkPermissionStatus()
            if currentStatus == .denied && self.isRecording {
                Logger.warning("Microphone permission revoked while recording", category: "RecordingManager")
                // Stop recording if permission was revoked
                // Note: This requires modelContext, so we'll handle via notification
                NotificationCenter.default.post(name: .stopRecordingFromKeyboard, object: nil)
                self.activeRecordingAlert = .permissionDenied
            }
        }
    }
    
    private func requestPermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - Duration Timer
    private func startDurationTimer() {
        // Atomically stop any existing timer before starting a new one
        stateQueue.sync {
            durationTimer?.invalidate()
            durationTimer = nil
        }
        
        currentDuration = 0
        // Optimized timer: use RunLoop.main for proper scheduling and ensure cleanup
        let newTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.currentDuration += 0.1
            }
        }
        
        stateQueue.sync {
            durationTimer = newTimer
        }
        RunLoop.main.add(newTimer, forMode: .common)
    }
    
    private func stopDurationTimer() {
        stateQueue.sync {
            durationTimer?.invalidate()
            durationTimer = nil
        }
    }
    
    // MARK: - Transcription
    private func transcribeInBackground(note: Transcription, audioFileName: String, recordingDuration: Double, modelContext: ModelContext, shouldStoreTranscript: Bool = false) {
        Logger.debug("transcribeInBackground() called - audioFileName: \(audioFileName), duration: \(recordingDuration)s, shouldStoreTranscript: \(shouldStoreTranscript)", category: "RecordingManager")
        
        Task {
            defer { 
                // Clean up recorder state
                recorder.currentRecordingURL = nil
                recorder.currentDuration = 0
            }
            
            let settings = AppSettings.shared
            
            // Use effective settings from selected mode
            let provider = settings.effectiveTranscriptionProvider
            let apiKey = settings.apiKey(for: provider)
            let model = settings.effectiveTranscriptionModel
            Logger.debug("Transcription provider: \(provider), model: \(model)", category: "RecordingManager")
            
            // If no API key, update note with error
            guard !apiKey.isEmpty else {
                Logger.error("No API key configured for provider: \(provider)", category: "RecordingManager")
                await MainActor.run {
                    note.transcriptionStatus = .failed
                    note.transcriptionError = "No API key configured"
                    modelContext.processPendingChanges()
                    try? modelContext.save()
                }
                return
            }
            
            do {
                // Resolve the relative path to absolute path for transcription
                let recordingsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Recordings")
                let fileURL = recordingsDir.appendingPathComponent(audioFileName)
                let service = TranscriptionServiceFactory.service(for: provider)
                let rawText = try await service.transcribeAudioFile(apiBaseURL: provider.baseURL, apiKey: apiKey, model: model, fileURL: fileURL, language: nil)
                
                // PERFORMANCE: Clean up transcription using pre-compiled regex patterns
                // This is faster than compiling regex on each call
                let cleanedText = Self.cleanTranscriptionText(rawText)
                
                // Auto-delete note if no audio was detected
                let isNoAudioDetected = cleanedText.isEmpty || 
                                       cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "no audio detected." ||
                                       cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "no audible content detected."
                
                if isNoAudioDetected {
                    Logger.info("No audio detected in recording, automatically deleting note", category: "RecordingManager")
                    await MainActor.run {
                        // Delete the note and its audio file
                        if let audioPath = note.fullAudioPath, FileManager.default.fileExists(atPath: audioPath) {
                            try? FileManager.default.removeItem(atPath: audioPath)
                        }
                        modelContext.delete(note)
                        do {
                            try modelContext.save()
                            Logger.info("Note deleted successfully (no audio detected)", category: "RecordingManager")
                        } catch {
                            Logger.error("Failed to delete note: \(error.localizedDescription)", category: "RecordingManager")
                        }
                    }
                    return // Exit early, don't process further
                }
                
                // Detect language early to apply Spanish correction if needed
                let preliminaryLanguage = detectLanguage(from: cleanedText)
                Logger.debug("Preliminary language detection: \(preliminaryLanguage ?? "en (default)")", category: "RecordingManager")
                
                // PERFORMANCE FIX: Update UI immediately with raw transcription (don't wait for enhancements)
                // This allows users to see the text right away while enhancements happen in background
                await MainActor.run {
                    Logger.debug("Updating note immediately with raw transcription (length: \(cleanedText.count))", category: "RecordingManager")
                    
                    note.text = cleanedText
                    note.transcriptionModelName = model
                    note.transcriptionStatus = .completed
                    
                    do {
                        modelContext.processPendingChanges()
                        try modelContext.save()
                        Logger.info("Note updated immediately with raw transcription", category: "RecordingManager")
                    } catch {
                        Logger.error("Failed to save note: \(error.localizedDescription)", category: "RecordingManager")
                    }
                }
                
                // PERFORMANCE OPTIMIZATION: Start translation early in parallel with enhancements
                // This allows translation to happen concurrently instead of waiting for all processing
                let detectedLanguageForTranslation = preliminaryLanguage ?? "en"
                let translationTask: Task<String?, Never>? = !cleanedText.isEmpty ? Task { [weak self] in
                    guard let self = self else { return nil }
                    Logger.debug("Starting early translation in parallel with enhancements", category: "RecordingManager")
                    do {
                        let translatedText = try await withThrowingTaskGroup(of: String.self) { group in
                            // Add translation task
                            group.addTask {
                                if detectedLanguageForTranslation == "es" {
                                    return try await self.translationService.translateToEnglish(text: cleanedText)
                                } else {
                                    return try await self.translationService.translateToSpanish(text: cleanedText)
                                }
                            }
                            
                            // Add timeout task (reduced from 30s to 15s for faster fallback)
                            group.addTask {
                                try await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
                                throw TranslationError.translationFailed("Translation timed out after 15 seconds")
                            }
                            
                            // Get first result (either translation or timeout)
                            let result = try await group.next()!
                            // Cancel remaining tasks
                            group.cancelAll()
                            return result
                        }
                        Logger.info("Early translation completed! Length: \(translatedText.count)", category: "RecordingManager")
                        return translatedText
                    } catch {
                        Logger.warning("Early translation failed: \(error.localizedDescription), will retry with enhanced text if available", category: "RecordingManager")
                        return nil
                    }
                } : nil
                
                // Now run enhancements in background (non-blocking) and update UI incrementally
                var enhancedText: String? = nil
                var postProcessingError: String? = nil
                var finalText = cleanedText
                
                // Automatic Spanish correction for better accuracy with accents (runs before user's post-processing)
                if preliminaryLanguage == "es" && !cleanedText.isEmpty {
                    Logger.debug("Spanish detected - applying automatic correction in background", category: "RecordingManager")
                    let llmProvider = settings.effectivePostProcessingProvider
                    let llmKey = settings.apiKey(for: llmProvider)
                    let llmModel = settings.effectivePostProcessingModel
                    
                    if !llmKey.isEmpty {
                        do {
                            let correctedText = try await postProcessor.correctSpanishTranscription(
                                provider: llmProvider,
                                apiKey: llmKey,
                                model: llmModel,
                                transcript: cleanedText
                            )
                            finalText = correctedText
                            enhancedText = correctedText
                            Logger.info("Spanish transcription corrected successfully", category: "RecordingManager")
                        } catch {
                            Logger.warning("Spanish correction failed: \(error.localizedDescription), using original transcription", category: "RecordingManager")
                            // Continue with original text if correction fails
                            finalText = cleanedText
                        }
                    } else {
                        Logger.warning("No API key for Spanish correction, skipping automatic correction", category: "RecordingManager")
                    }
                }
                
                // Optional user-configured post-processing (runs after Spanish correction if applicable)
                if settings.effectiveIsPostProcessingEnabled {
                    let ppPrompt = settings.effectiveCustomPrompt
                    if !ppPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let llmProvider = settings.effectivePostProcessingProvider
                        let llmKey = settings.apiKey(for: llmProvider)
                        let llmModel = settings.effectivePostProcessingModel
                        if !llmKey.isEmpty {
                            do {
                                // Use corrected text if available, otherwise use cleaned text
                                let textToProcess = enhancedText ?? cleanedText
                                finalText = try await postProcessor.postProcessTranscript(provider: llmProvider, apiKey: llmKey, model: llmModel, prompt: ppPrompt, transcript: textToProcess)
                                enhancedText = finalText
                            } catch {
                                postProcessingError = "Post-processing failed: \(error.localizedDescription)"
                                // Keep the Spanish-corrected text if available, otherwise use cleaned text
                                finalText = enhancedText ?? cleanedText
                            }
                        }
                    }
                }
                
                // Final language detection (after all processing)
                let textToTranslate = enhancedText ?? cleanedText
                let detectedLanguage = detectLanguage(from: textToTranslate)
                // detectLanguage only returns "en" or "es" (or nil, which defaults to English)
                Logger.debug("Detected language: \(detectedLanguage ?? "en (default)")", category: "RecordingManager")
                
                // PERFORMANCE OPTIMIZATION: Batch all enhancement updates into a single save
                // This reduces blocking operations from multiple saves to just one
                await MainActor.run {
                    // Update enhanced text if available
                    if let enhanced = enhancedText {
                        note.enhancedText = enhanced
                    }
                    
                    // Update metadata
                    note.detectedLanguage = detectedLanguage
                    if settings.effectiveIsPostProcessingEnabled && enhancedText != nil {
                        note.aiEnhancementModelName = settings.effectivePostProcessingModel
                    }
                    if let error = postProcessingError {
                        note.transcriptionError = error
                    }
                    
                    // If this was stopped from keyboard, store transcript for keyboard to retrieve
                    if shouldStoreTranscript {
                        // Use enhanced text if available, otherwise use cleaned text
                        let textToStore = enhancedText ?? cleanedText
                        if !textToStore.isEmpty {
                            coordinator.storeTranscript(textToStore)
                            Logger.debug("Transcript stored for keyboard (length: \(textToStore.count))", category: "RecordingManager")
                        }
                    }
                    
                    // Single save for all enhancements
                    modelContext.processPendingChanges()
                    try? modelContext.save()
                    Logger.debug("Note updated with all enhancements in single save", category: "RecordingManager")
                }
                
                // Handle translation: use early translation if available, otherwise translate enhanced text
                if !textToTranslate.isEmpty {
                    Logger.debug("Processing translation for text: '\(textToTranslate.prefix(50))...'", category: "RecordingManager")
                    
                    // Wait for early translation if it's still running, or start new translation with enhanced text
                    let translatedText: String?
                    if let earlyTask = translationTask {
                        // Check if early translation completed
                        if let earlyResult = await earlyTask.value {
                            translatedText = earlyResult
                            Logger.debug("Using early translation result", category: "RecordingManager")
                        } else {
                            // Early translation failed or timed out, try again with enhanced text if different
                            if textToTranslate != cleanedText {
                                Logger.debug("Retrying translation with enhanced text", category: "RecordingManager")
                                do {
                                    translatedText = try await withThrowingTaskGroup(of: String.self) { group in
                                        group.addTask {
                                            if detectedLanguage == "es" {
                                                return try await self.translationService.translateToEnglish(text: textToTranslate)
                                            } else {
                                                return try await self.translationService.translateToSpanish(text: textToTranslate)
                                            }
                                        }
                                        group.addTask {
                                            try await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
                                            throw TranslationError.translationFailed("Translation timed out after 15 seconds")
                                        }
                                        let result = try await group.next()!
                                        group.cancelAll()
                                        return result
                                    }
                                } catch {
                                    Logger.error("Retry translation failed: \(error.localizedDescription)", category: "RecordingManager")
                                    translatedText = nil
                                }
                            } else {
                                translatedText = nil
                            }
                        }
                    } else {
                        // No early translation task, translate now
                        do {
                            translatedText = try await withThrowingTaskGroup(of: String.self) { group in
                                group.addTask {
                                    if detectedLanguage == "es" {
                                        return try await self.translationService.translateToEnglish(text: textToTranslate)
                                    } else {
                                        return try await self.translationService.translateToSpanish(text: textToTranslate)
                                    }
                                }
                                group.addTask {
                                    try await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
                                    throw TranslationError.translationFailed("Translation timed out after 15 seconds")
                                }
                                let result = try await group.next()!
                                group.cancelAll()
                                return result
                            }
                        } catch {
                            Logger.error("Translation failed: \(error.localizedDescription)", category: "RecordingManager")
                            translatedText = nil
                        }
                    }
                    
                    // Update note with translation on main thread (single save)
                    if let translated = translatedText {
                        await MainActor.run {
                            note.translatedText = translated
                            modelContext.processPendingChanges()
                            try? modelContext.save()
                            Logger.info("Translation completed and saved! Length: \(translated.count)", category: "RecordingManager")
                        }
                    }
                } else {
                    Logger.warning("Text to translate is empty, skipping translation", category: "RecordingManager")
                }
                
            } catch {
                // Update note with error on main thread
                Logger.error("Transcription failed with error: \(error.localizedDescription)", category: "RecordingManager")
                await MainActor.run {
                    note.transcriptionStatus = .failed
                    note.transcriptionError = error.localizedDescription
                    modelContext.processPendingChanges()
                    try? modelContext.save()
                    
                    // If this was stopped from keyboard and transcription failed, store error message
                    if shouldStoreTranscript {
                        let errorMessage = "Transcription failed: \(error.localizedDescription)"
                        coordinator.storeTranscript(errorMessage)
                    }
                }
            }
        }
    }
    
    // MARK: - Text Cleaning
    
    /// Clean transcription text using pre-compiled regex patterns for better performance
    /// This is faster than compiling regex on each call
    /// Made internal so it can be reused by TranscriptionRetryService
    static func cleanTranscriptionText(_ text: String) -> String {
        // Trim whitespace first
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Replace multiple newlines with double newline using pre-compiled regex
        cleaned = doubleNewlineRegex.stringByReplacingMatches(
            in: cleaned,
            options: [],
            range: NSRange(location: 0, length: cleaned.utf16.count),
            withTemplate: "\n\n"
        )
        
        // Replace multiple spaces/tabs with single space using pre-compiled regex
        cleaned = whitespaceRegex.stringByReplacingMatches(
            in: cleaned,
            options: [],
            range: NSRange(location: 0, length: cleaned.utf16.count),
            withTemplate: " "
        )
        
        return cleaned
    }
    
    // MARK: - Language Detection
    
    /// Detect language from text using simple heuristics
    /// Only supports English and Spanish - returns "es" for Spanish, "en" for English (or nil which defaults to English)
    /// Other languages are not supported and will default to English
    /// Results are cached for performance using NSCache (LRU behavior with automatic memory management)
    private func detectLanguage(from text: String) -> String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        
        // Create a better hash key using the normalized text (lowercased, trimmed)
        // This reduces collisions compared to String.hashValue
        let normalizedText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = normalizedText as NSString
        
        // Check cache first
        if let cached = languageDetectionCache.object(forKey: cacheKey) {
            return cached as String
        }
        
        let lowercased = text.lowercased()
        
        // Common Spanish words and patterns
        let spanishIndicators = [
            "el ", "la ", "los ", "las ", "un ", "una ", "unos ", "unas ",
            "que ", "de ", "y ", "a ", "en ", "es ", "son ", "está ", "están ",
            "con ", "por ", "para ", "del ", "al ", "más ", "muy ", "también ",
            "pero ", "como ", "cuando ", "donde ", "porque ", "si ", "no ",
            "tiene ", "tienen ", "fue ", "fueron ", "ser ", "estar ",
            "é", "á", "í", "ó", "ú", "ñ", "¿", "¡"
        ]
        
        // Common English words
        let englishIndicators = [
            "the ", "a ", "an ", "and ", "or ", "but ", "in ", "on ", "at ",
            "to ", "for ", "of ", "with ", "from ", "by ", "is ", "are ",
            "was ", "were ", "have ", "has ", "had ", "will ", "would ",
            "can ", "could ", "should ", "may ", "might ", "this ", "that ",
            "these ", "those ", "what ", "when ", "where ", "why ", "how "
        ]
        
        var spanishScore = 0
        var englishScore = 0
        
        // Count Spanish indicators
        for indicator in spanishIndicators {
            if lowercased.contains(indicator) {
                spanishScore += 1
            }
        }
        
        // Count English indicators
        for indicator in englishIndicators {
            if lowercased.contains(indicator) {
                englishScore += 1
            }
        }
        
        // Check for Spanish-specific characters
        if lowercased.contains("ñ") || lowercased.contains("á") || lowercased.contains("é") ||
           lowercased.contains("í") || lowercased.contains("ó") || lowercased.contains("ú") ||
           lowercased.contains("¿") || lowercased.contains("¡") {
            spanishScore += 3
        }
        
        Logger.debug("Language detection: Spanish score: \(spanishScore), English score: \(englishScore)", category: "RecordingManager")
        
        // Determine result
        let result: String?
        if spanishScore > englishScore + 2 {
            result = "es"
        } else if englishScore >= spanishScore {
            result = "en"
        } else {
            result = "en" // Default to English
        }
        
        // Cache result using NSCache (automatically handles memory pressure and eviction)
        if let resultString = result {
            // Use text length as cost to help NSCache manage memory better
            let cost = normalizedText.count
            languageDetectionCache.setObject(resultString as NSString, forKey: cacheKey, cost: cost)
        }
        
        return result
    }
}
