import Foundation

/// Handles communication between the main VoiceInk app and the keyboard extension
/// Uses App Groups + Darwin Notifications for reliable iOS-native communication
final class AppGroupCoordinator {
    static let shared = AppGroupCoordinator()
    
    // MARK: - Constants
    private let appGroupIdentifier = "group.com.pawsitivegames.VoiceInk"
    
    // UserDefaults keys for persistent state
    private enum UserDefaultsKeys {
        static let shouldStartRecording = "shouldStartRecording"
        static let shouldStopRecording = "shouldStopRecording"
        static let isRecording = "isRecording"
        static let lastRecordingTimestamp = "lastRecordingTimestamp"
        static let transcriptText = "transcriptText"
        static let transcriptReady = "transcriptReady"
        static let transcriptTimestamp = "transcriptTimestamp"
        static let stopRequestTimestamp = "stopRequestTimestamp" // Track when stop was requested
    }
    
    // Darwin notification names for real-time communication
    private enum NotificationNames {
        static let startRecording = "com.prakashjoshipax.VoiceInk.startRecording"
        static let stopRecording = "com.prakashjoshipax.VoiceInk.stopRecording"
        static let recordingStateChanged = "com.prakashjoshipax.VoiceInk.recordingStateChanged"
        static let transcriptReady = "com.prakashjoshipax.VoiceInk.transcriptReady"
    }
    
    // MARK: - Properties
    private let sharedDefaults: UserDefaults?
    private let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
    
    // Callbacks for the main app
    var onStartRecordingRequested: (() -> Void)?
    var onStopRecordingRequested: (() -> Void)?
    
    // MARK: - Initialization
    private init() {
        sharedDefaults = UserDefaults(suiteName: appGroupIdentifier)
        setupNotificationObservers()
    }
    
    deinit {
        removeNotificationObservers()
    }
    
    // MARK: - Public Interface for Keyboard Extension
    
    /// Call this from the keyboard extension to request recording start
    func requestStartRecording() {
        let timestamp = Date().timeIntervalSince1970
        
        // Set persistent flag
        sharedDefaults?.set(true, forKey: UserDefaultsKeys.shouldStartRecording)
        sharedDefaults?.set(timestamp, forKey: UserDefaultsKeys.lastRecordingTimestamp)
        
        // Send immediate notification
        postDarwinNotification(NotificationNames.startRecording)
    }
    
    /// Call this from the keyboard extension to request recording stop
    func requestStopRecording() {
        let timestamp = Date().timeIntervalSince1970
        
        print("🛑 AppGroupCoordinator: requestStopRecording called")
        
        // Set persistent flag
        sharedDefaults?.set(true, forKey: UserDefaultsKeys.shouldStopRecording)
        sharedDefaults?.set(timestamp, forKey: UserDefaultsKeys.lastRecordingTimestamp)
        // Store stop request timestamp to match with transcript
        sharedDefaults?.set(timestamp, forKey: UserDefaultsKeys.stopRequestTimestamp)
        sharedDefaults?.synchronize()
        
        print("🛑 AppGroupCoordinator: Stop flag set in UserDefaults")
        
        // Send immediate notification
        postDarwinNotification(NotificationNames.stopRecording)
        print("🛑 AppGroupCoordinator: Darwin notification posted")
    }
    
    /// Get current recording state (for keyboard UI updates)
    var isRecording: Bool {
        let storedState = sharedDefaults?.bool(forKey: UserDefaultsKeys.isRecording) ?? false
        let timestamp = sharedDefaults?.double(forKey: UserDefaultsKeys.lastRecordingTimestamp) ?? 0
        let currentTime = Date().timeIntervalSince1970
        
        // If the stored state is more than 30 seconds old, consider it stale
        if storedState && (currentTime - timestamp) > 30 {
            print("⚠️ Recording state appears stale, clearing it")
            updateRecordingState(false)
            return false
        }
        
        return storedState
    }
    
    // MARK: - Public Interface for Main App
    
    /// Call this from the main app to update recording state
    func updateRecordingState(_ isRecording: Bool) {
        sharedDefaults?.set(isRecording, forKey: UserDefaultsKeys.isRecording)
        // Update timestamp whenever state changes
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: UserDefaultsKeys.lastRecordingTimestamp)
        
        // Notify keyboard of state change
        postDarwinNotification(NotificationNames.recordingStateChanged)
        
        print("📡 Updated recording state: \(isRecording)")
    }
    
    /// Check and consume start recording flag (returns true if should start)
    func checkAndConsumeStartRecordingFlag() -> Bool {
        guard let defaults = sharedDefaults else { return false }
        
        let shouldStart = defaults.bool(forKey: UserDefaultsKeys.shouldStartRecording)
        if shouldStart {
            // Consume the flag
            defaults.set(false, forKey: UserDefaultsKeys.shouldStartRecording)
            return true
        }
        return false
    }
    
    /// Check and consume stop recording flag (returns true if should stop)
    func checkAndConsumeStopRecordingFlag() -> Bool {
        guard let defaults = sharedDefaults else { return false }
        
        let shouldStop = defaults.bool(forKey: UserDefaultsKeys.shouldStopRecording)
        if shouldStop {
            // Consume the flag
            defaults.set(false, forKey: UserDefaultsKeys.shouldStopRecording)
            return true
        }
        return false
    }
    
    // MARK: - Transcript Management
    
    /// Store transcript text from main app (called when transcription completes)
    func storeTranscript(_ text: String) {
        guard let defaults = sharedDefaults else { return }
        
        let timestamp = Date().timeIntervalSince1970
        defaults.set(text, forKey: UserDefaultsKeys.transcriptText)
        defaults.set(true, forKey: UserDefaultsKeys.transcriptReady)
        defaults.set(timestamp, forKey: UserDefaultsKeys.transcriptTimestamp)
        defaults.synchronize() // Ensure it's written immediately
        
        // Notify keyboard that transcript is ready
        postDarwinNotification(NotificationNames.transcriptReady)
        
        print("📝 Stored transcript: \(text.prefix(50))... (timestamp: \(timestamp))")
    }
    
    /// Clear any old/stale transcript (called when starting a new recording or stop request)
    func clearOldTranscript() {
        guard let defaults = sharedDefaults else { return }
        
        defaults.removeObject(forKey: UserDefaultsKeys.transcriptText)
        defaults.set(false, forKey: UserDefaultsKeys.transcriptReady)
        defaults.removeObject(forKey: UserDefaultsKeys.transcriptTimestamp)
        defaults.synchronize()
        
        print("🧹 Cleared old transcript")
    }
    
    /// Get transcript without consuming it (for retry attempts)
    /// - Parameter afterTimestamp: Only return transcript if it was created after this timestamp
    func getTranscriptWithoutConsuming(afterTimestamp: TimeInterval = 0) -> String? {
        guard let defaults = sharedDefaults else {
            print("⚠️ getTranscriptWithoutConsuming: No shared defaults available")
            return nil
        }
        
        let isReady = defaults.bool(forKey: UserDefaultsKeys.transcriptReady)
        guard isReady else { return nil }
        
        // Check if transcript timestamp matches our stop request
        let transcriptTimestamp = defaults.double(forKey: UserDefaultsKeys.transcriptTimestamp)
        let stopRequestTimestamp = defaults.double(forKey: UserDefaultsKeys.stopRequestTimestamp)
        
        // Simplified: Since we clear old transcripts when starting/stopping,
        // we can accept any ready transcript. The timestamp check was causing issues.
        // If afterTimestamp is provided and transcript is significantly older, reject it
        if afterTimestamp > 0 {
            let timeDiff = transcriptTimestamp - afterTimestamp
            // Only reject if transcript is more than 30 seconds before stop request
            if timeDiff < -30.0 {
                print("⚠️ Transcript timestamp (\(transcriptTimestamp)) is more than 30s before stop request (\(afterTimestamp)), ignoring (diff: \(timeDiff))")
                return nil
            }
        }
        
        // Get the transcript text without consuming it
        guard let text = defaults.string(forKey: UserDefaultsKeys.transcriptText), !text.isEmpty else {
            return nil
        }
        
        return text
    }
    
    /// Get and consume transcript (returns text if available, nil otherwise)
    /// This should be called from keyboard extension to get the transcript
    /// - Parameter afterTimestamp: Only return transcript if it was created after this timestamp
    func getAndConsumeTranscript(afterTimestamp: TimeInterval = 0) -> String? {
        guard let defaults = sharedDefaults else {
            print("⚠️ getAndConsumeTranscript: No shared defaults available")
            return nil
        }
        
        let isReady = defaults.bool(forKey: UserDefaultsKeys.transcriptReady)
        print("🔍 getAndConsumeTranscript: isReady=\(isReady), afterTimestamp=\(afterTimestamp)")
        guard isReady else { return nil }
        
        // Check if transcript timestamp matches our stop request
        let transcriptTimestamp = defaults.double(forKey: UserDefaultsKeys.transcriptTimestamp)
        let stopRequestTimestamp = defaults.double(forKey: UserDefaultsKeys.stopRequestTimestamp)
        
        print("🔍 Timestamp check: transcript=\(transcriptTimestamp), stopRequest=\(stopRequestTimestamp), afterTimestamp=\(afterTimestamp)")
        
        // Simplified: Since we clear old transcripts when starting/stopping,
        // we can accept any ready transcript. The timestamp check was causing issues.
        // If afterTimestamp is provided and transcript is significantly older, reject it
        if afterTimestamp > 0 {
            let timeDiff = transcriptTimestamp - afterTimestamp
            // Only reject if transcript is more than 30 seconds before stop request
            // This handles edge cases while still preventing very old transcripts
            if timeDiff < -30.0 {
                print("⚠️ Transcript timestamp (\(transcriptTimestamp)) is more than 30s before stop request (\(afterTimestamp)), ignoring (diff: \(timeDiff))")
                return nil
            }
            print("✅ Transcript timestamp check passed (diff: \(timeDiff)s)")
        } else {
            // No timestamp provided, accept any ready transcript
            print("ℹ️ No timestamp filter, accepting any ready transcript")
        }
        
        // Get the transcript text
        guard let text = defaults.string(forKey: UserDefaultsKeys.transcriptText), !text.isEmpty else {
            // Clear the ready flag if text is empty
            print("⚠️ Transcript text is empty")
            defaults.set(false, forKey: UserDefaultsKeys.transcriptReady)
            return nil
        }
        
        print("✅ Found transcript text: \(text.prefix(50))...")
        
        // Consume the transcript (clear it after reading)
        defaults.removeObject(forKey: UserDefaultsKeys.transcriptText)
        defaults.set(false, forKey: UserDefaultsKeys.transcriptReady)
        defaults.removeObject(forKey: UserDefaultsKeys.transcriptTimestamp)
        defaults.removeObject(forKey: UserDefaultsKeys.stopRequestTimestamp)
        defaults.synchronize()
        
        print("📤 Retrieved and consumed transcript: \(text.prefix(50))... (timestamp: \(transcriptTimestamp))")
        return text
    }
    
    /// Check if transcript is ready (for keyboard to poll)
    var isTranscriptReady: Bool {
        guard let defaults = sharedDefaults else { return false }
        
        let isReady = defaults.bool(forKey: UserDefaultsKeys.transcriptReady)
        guard isReady else { return false }
        
        // Check if transcript is not stale (older than 5 minutes)
        let timestamp = defaults.double(forKey: UserDefaultsKeys.transcriptTimestamp)
        let currentTime = Date().timeIntervalSince1970
        
        if (currentTime - timestamp) > 300 { // 5 minutes
            // Transcript is stale, clear it
            defaults.set(false, forKey: UserDefaultsKeys.transcriptReady)
            defaults.removeObject(forKey: UserDefaultsKeys.transcriptText)
            defaults.removeObject(forKey: UserDefaultsKeys.transcriptTimestamp)
            return false
        }
        
        return true
    }
    
    // MARK: - Darwin Notifications (Real-time Communication)
    
    private func setupNotificationObservers() {
        guard let center = notificationCenter else { return }
        
        // Observe start recording notifications
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { (center, observer, name, object, userInfo) in
                guard let observer = observer else { return }
                let coordinator = Unmanaged<AppGroupCoordinator>.fromOpaque(observer).takeUnretainedValue()
                coordinator.handleStartRecordingNotification()
            },
            NotificationNames.startRecording as CFString,
            nil,
            .deliverImmediately
        )
        
        // Observe stop recording notifications
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { (center, observer, name, object, userInfo) in
                guard let observer = observer else { return }
                let coordinator = Unmanaged<AppGroupCoordinator>.fromOpaque(observer).takeUnretainedValue()
                coordinator.handleStopRecordingNotification()
            },
            NotificationNames.stopRecording as CFString,
            nil,
            .deliverImmediately
        )
    }
    
    private func removeNotificationObservers() {
        guard let center = notificationCenter else { return }
        CFNotificationCenterRemoveEveryObserver(center, Unmanaged.passUnretained(self).toOpaque())
    }
    
    private func postDarwinNotification(_ name: String) {
        guard let center = notificationCenter else { return }
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(name as CFString),
            nil,
            nil,
            true
        )
    }
    
    // MARK: - Notification Handlers
    
    private func handleStartRecordingNotification() {
        DispatchQueue.main.async { [weak self] in
            self?.onStartRecordingRequested?()
        }
    }
    
    private func handleStopRecordingNotification() {
        print("🛑 AppGroupCoordinator: Received stop recording Darwin notification")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                print("⚠️ AppGroupCoordinator: self is nil in handleStopRecordingNotification")
                return
            }
            if let callback = self.onStopRecordingRequested {
                print("🛑 AppGroupCoordinator: Calling onStopRecordingRequested callback")
                callback()
            } else {
                print("⚠️ AppGroupCoordinator: onStopRecordingRequested callback is nil")
            }
        }
    }
    
    // MARK: - Debug Helpers
    
    /// Clear all shared data (useful for debugging)
    func clearAllSharedData() {
        guard let defaults = sharedDefaults else { return }
        defaults.removeObject(forKey: UserDefaultsKeys.shouldStartRecording)
        defaults.removeObject(forKey: UserDefaultsKeys.shouldStopRecording)
        defaults.removeObject(forKey: UserDefaultsKeys.isRecording)
        defaults.removeObject(forKey: UserDefaultsKeys.lastRecordingTimestamp)
        defaults.removeObject(forKey: UserDefaultsKeys.transcriptText)
        defaults.removeObject(forKey: UserDefaultsKeys.transcriptReady)
        defaults.removeObject(forKey: UserDefaultsKeys.transcriptTimestamp)
        defaults.removeObject(forKey: UserDefaultsKeys.stopRequestTimestamp)
    }
    
    /// Get debug info about current state
    func getDebugInfo() -> [String: Any] {
        guard let defaults = sharedDefaults else { return ["error": "No shared defaults"] }
        
        return [
            "shouldStartRecording": defaults.bool(forKey: UserDefaultsKeys.shouldStartRecording),
            "shouldStopRecording": defaults.bool(forKey: UserDefaultsKeys.shouldStopRecording),
            "isRecording": defaults.bool(forKey: UserDefaultsKeys.isRecording),
            "lastRecordingTimestamp": defaults.double(forKey: UserDefaultsKeys.lastRecordingTimestamp),
            "transcriptReady": defaults.bool(forKey: UserDefaultsKeys.transcriptReady),
            "transcriptText": defaults.string(forKey: UserDefaultsKeys.transcriptText)?.prefix(50) ?? "nil",
            "transcriptTimestamp": defaults.double(forKey: UserDefaultsKeys.transcriptTimestamp),
            "appGroupIdentifier": appGroupIdentifier
        ]
    }
}
