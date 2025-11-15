//
//  KeyboardViewController.swift
//  VoiceInkKeyboard
//
//  Created by Prakash Joshi on 28/08/2025.
//

import UIKit
import KeyboardKit
import os

class KeyboardViewController: KeyboardInputViewController {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "KeyboardExtension")
    
    var recordButton: UIButton!
    private let coordinator = AppGroupCoordinator.shared
    private var recordingStatusTimer: Timer?
    private var transcriptPollingTimer: Timer?
    private var transcriptPollingStartTime: Date?
    private var stopRequestTimestamp: TimeInterval = 0 // Track when stop was requested
    private let transcriptPollingTimeout: TimeInterval = 60.0 // 60 seconds timeout
    private var pendingTranscript: String? // Store transcript locally for retry attempts
    private var transcriptInsertionAttempts: Int = 0 // Track insertion attempts
    
    deinit {
        recordingStatusTimer?.invalidate()
        recordingStatusTimer = nil
        transcriptPollingTimer?.invalidate()
        transcriptPollingTimer = nil
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupKeyboard()
        setupRecordingStatusMonitoring()
        setupTranscriptNotificationObserver()
    }
    
    private func setupKeyboard() {
        // Setup KeyboardKit with default configuration
        setupKeyboardKit()
        
        // Add our custom record button at the top
        setupRecordButton()
    }
    
    private func setupKeyboardKit() {
        // KeyboardInputViewController automatically sets up the keyboard
        // We can customize the keyboard appearance here if needed
        
        // Make the keyboard more compact
        setupCompactKeyboard()
    }
    
    private func setupCompactKeyboard() {
        // Customize KeyboardKit's key styling to make keys more compact
        // This requires working with KeyboardKit's styling system
        
        // Note: KeyboardKit's styling is complex and may require KeyboardKit Pro
        // For now, we'll keep the default keyboard layout
        // Individual key customization would require:
        // 1. Custom KeyboardStyleProvider
        // 2. Custom KeyboardLayoutProvider  
        // 3. Overriding key button styles
        
    }
    
    private func setupRecordButton() {
        // Create the native iOS-style record button
        recordButton = UIButton(type: .system)
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        
        // Configure for idle state initially
        configureButtonForIdleState()
        
        // Add native iOS styling
        recordButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        recordButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)
        
        // Native iOS shadow and styling
        recordButton.layer.shadowColor = UIColor.black.cgColor
        recordButton.layer.shadowOffset = CGSize(width: 0, height: 1)
        recordButton.layer.shadowOpacity = 0.2
        recordButton.layer.shadowRadius = 2
        
        // Add subtle border for better definition
        recordButton.layer.borderWidth = 0.5
        recordButton.layer.borderColor = UIColor.separator.cgColor
        
        // Add button to main view
        view.addSubview(recordButton)
        
        // Set up constraints - position in top center with safe margins
        NSLayoutConstraint.activate([
            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            recordButton.heightAnchor.constraint(equalToConstant: 32),
            recordButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])
        
        // Ensure button stays on top
        view.bringSubviewToFront(recordButton)
    }
    
    private func configureButtonForIdleState() {
        // Use SF Symbol for microphone
        let microphoneConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let microphoneImage = UIImage(systemName: "mic.fill", withConfiguration: microphoneConfig)
        
        recordButton.setImage(microphoneImage, for: .normal)
        recordButton.setTitle(" Record", for: .normal)
        recordButton.backgroundColor = UIColor.systemBlue
        recordButton.setTitleColor(.white, for: .normal)
        recordButton.tintColor = .white
        
        // Ensure image and text are properly aligned
        recordButton.semanticContentAttribute = .forceLeftToRight
        recordButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 4)
        recordButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
    }
    
    private func configureButtonForRecordingState() {
        // Use SF Symbol for stop
        let stopConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let stopImage = UIImage(systemName: "stop.fill", withConfiguration: stopConfig)
        
        recordButton.setImage(stopImage, for: .normal)
        recordButton.setTitle(" Stop", for: .normal)
        recordButton.backgroundColor = UIColor.systemRed
        recordButton.setTitleColor(.white, for: .normal)
        recordButton.tintColor = .white
        
        // Ensure image and text are properly aligned
        recordButton.semanticContentAttribute = .forceLeftToRight
        recordButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 4)
        recordButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Re-add and ensure record button stays on top after KeyboardKit layout
        if let button = recordButton {
            if button.superview == nil {
                view.addSubview(button)
            }
            view.bringSubviewToFront(button)
            
            // Ensure proper capsule shape after layout
            DispatchQueue.main.async {
                button.layer.cornerRadius = button.frame.height / 2
            }
        } else {
            // no-op
        }
        
        // Update button state immediately when keyboard appears
        // This ensures the button shows the correct state when user switches back
        updateButtonAppearanceBasedOnState()
        
        // Restart monitoring if timer was stopped
        if recordingStatusTimer == nil {
            setupRecordingStatusMonitoring()
        }
        
        // Check if there's a pending transcript to insert when keyboard becomes active
        // This handles the case where transcript was ready but keyboard wasn't active
        // Try multiple times with increasing delays to catch the keyboard when it's ready
        if coordinator.isTranscriptReady {
            logger.info("📝 Keyboard: Found pending transcript when keyboard appeared, will attempt to insert")
            
            // Try immediately
            tryInsertPendingTranscript()
            
            // Try multiple times with increasing delays to ensure we catch it when keyboard is fully ready
            let delays: [TimeInterval] = [0.1, 0.2, 0.3, 0.5, 0.8, 1.0]
            for delay in delays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self else { return }
                    // Only try if transcript is still ready (hasn't been consumed)
                    if self.coordinator.isTranscriptReady {
                        self.tryInsertPendingTranscript()
                    }
                }
            }
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Re-add button if KeyboardKit removed it
        if let button = recordButton, button.superview == nil {
            view.addSubview(button)
        }
        
        // Ensure button is still visible after layout
        if let button = recordButton {
            view.bringSubviewToFront(button)
            
            // Make button fully capsule-shaped based on its actual height
            button.layer.cornerRadius = button.frame.height / 2
        }
    }
    
    @objc private func recordButtonTapped() {
        // Add native iOS button press animation
        addButtonPressAnimation()
        
        // Provide haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        if coordinator.isRecording {
            // Stop recording
            logger.info("🛑 Keyboard: Stop button pressed, requesting stop recording")
            
            // Clear any old/stale transcript before starting new polling
            // This ensures we don't get a transcript from a previous recording
            coordinator.clearOldTranscript()
            
            // Record when we requested stop (to match with transcript timestamp)
            stopRequestTimestamp = Date().timeIntervalSince1970
            
            coordinator.requestStopRecording()
            logger.info("🛑 Keyboard: Stop request sent, starting transcript polling (timestamp: \(self.stopRequestTimestamp))")
            updateButtonAppearanceBasedOnState()
            // Start polling for transcript
            startTranscriptPolling()
        } else {
            // Start recording by opening main app
            // Clear any old transcript when starting new recording
            coordinator.clearOldTranscript()
            // Reset stop request timestamp
            stopRequestTimestamp = 0
            openMainAppForRecording()
        }
    }
    
    private func addButtonPressAnimation() {
        // Native iOS button press animation - scale down then back up
        UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseInOut], animations: {
            self.recordButton.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseInOut], animations: {
                self.recordButton.transform = CGAffineTransform.identity
            })
        }
    }
    
    private func openMainAppForRecording() {
        // iOS keyboard extensions have severe limitations with audio recording
        // The correct approach is to simply open the main app and let user record there
        
        // Try multiple approaches to open the main app
        if let url = URL(string: "voiceink://record") {
            // Method 1: Try extensionContext.open (primary method)
            extensionContext?.open(url) { success in
                if success {
                    self.logger.info("✅ Opened main app via extensionContext")
                } else {
                    self.logger.warning("❌ extensionContext.open failed, trying alternative methods")
                    DispatchQueue.main.async {
                        self.tryAlternativeURLOpening(url)
                    }
                }
            }
        } else {
            // Fallback: Show message to user
            showUserMessage()
        }
    }
    
    private func tryAlternativeURLOpening(_ url: URL) {
        // Try UIApplication directly if available
        if let sharedApp = UIApplication.value(forKeyPath: "sharedApplication") as? UIApplication {
            if sharedApp.canOpenURL(url) {
                sharedApp.open(url, options: [:]) { success in
                    if success {
                        self.logger.info("✅ Opened main app via UIApplication.open")
                    } else {
                        self.logger.error("❌ UIApplication.open failed")
                        self.showUserMessage()
                    }
                }
                return
            }
        }
        
        // Fallback: Try responder chain method
        openURLViaResponderChain(url)
    }
    
    private func openURLViaResponderChain(_ url: URL) {
        // iOS 18 workaround: Use responder chain to open URL
        var responder: UIResponder? = self
        let selector = sel_registerName("openURL:")
        
        while let r = responder, !r.responds(to: selector) {
            responder = r.next
        }
        
        if let responder = responder {
            _ = responder.perform(selector, with: url)
            logger.info("✅ Attempted to open main app via responder chain")
            // Don't assume success since we can't get feedback from this method
        } else {
            logger.error("❌ All URL opening methods failed")
            showUserMessage()
        }
    }
    
    private func showUserMessage() {
        // Last resort: Update button to show user should open main app manually
        let appConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let appImage = UIImage(systemName: "app", withConfiguration: appConfig)
        
        recordButton.setImage(appImage, for: .normal)
        recordButton.setTitle(" Open VoiceInk", for: .normal)
        recordButton.backgroundColor = UIColor.systemOrange
        recordButton.setTitleColor(.white, for: .normal)
        recordButton.tintColor = .white
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.configureButtonForIdleState()
        }
    }
    
    private func setupRecordingStatusMonitoring() {
        // Stop any existing timer
        recordingStatusTimer?.invalidate()
        
        // Monitor recording status every 0.5 seconds
        // Use common run loop modes so timer works even when keyboard is active
        recordingStatusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateButtonAppearanceBasedOnState()
        }
        
        // Add to common run loop modes to ensure it runs when keyboard is active
        if let timer = recordingStatusTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
        
        // Initial state update
        updateButtonAppearanceBasedOnState()
    }
    
    private func startTranscriptPolling() {
        // Stop any existing polling
        stopTranscriptPolling()
        
        // Record start time for timeout
        transcriptPollingStartTime = Date()
        
        logger.info("🔄 Keyboard: Starting transcript polling (stopRequestTimestamp: \(self.stopRequestTimestamp))")
        
        // Start with aggressive polling (every 0.1 seconds) to catch transcript as soon as it's ready
        transcriptPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkForTranscript()
        }
        
        // Add to common run loop modes
        if let timer = transcriptPollingTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
        
        // Also check immediately
        checkForTranscript()
    }
    
    private func stopTranscriptPolling() {
        transcriptPollingTimer?.invalidate()
        transcriptPollingTimer = nil
        transcriptPollingStartTime = nil
    }
    
    private func checkForTranscript() {
        // Check for timeout
        if let startTime = transcriptPollingStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > transcriptPollingTimeout {
                logger.warning("⏱️ Keyboard: Transcript polling timed out after \(self.transcriptPollingTimeout) seconds")
                stopTranscriptPolling()
                return
            }
        }
        
        // Check if transcript is ready
        let isReady = coordinator.isTranscriptReady
        if !isReady {
            // Only log every 50th check to avoid spam (every 5 seconds with 0.1s interval)
            if let startTime = transcriptPollingStartTime {
                let elapsed = Date().timeIntervalSince(startTime)
                if Int(elapsed * 10) % 50 == 0 { // Log every 5 seconds
                    logger.debug("🔄 Keyboard: Polling for transcript... (elapsed: \(Int(elapsed))s)")
                }
            }
            return
        }
        
        logger.info("✅ Keyboard: Transcript is ready, attempting to insert...")
        
        // Try to insert the transcript - be more aggressive about it
        attemptTranscriptInsertion()
    }
    
    private func attemptTranscriptInsertion() {
        // If we already have a pending transcript, use it (for retries)
        if let existingTranscript = pendingTranscript {
            logger.info("🔄 Keyboard: Retrying with existing pending transcript (\(existingTranscript.count) chars)")
            tryInsertTranscriptWithRetries(existingTranscript)
            return
        }
        
        // Get the transcript - don't consume it yet, store it locally for retries
        guard coordinator.isTranscriptReady else {
            logger.warning("⚠️ Keyboard: Transcript not ready yet")
            return
        }
        
        // Get transcript without consuming it - we'll consume after successful insertion
        guard let transcript = coordinator.getTranscriptWithoutConsuming(afterTimestamp: stopRequestTimestamp) else {
            logger.warning("⚠️ Keyboard: Failed to retrieve transcript, will keep trying...")
            return
        }
        
        logger.info("✅ Keyboard: Got transcript (\(transcript.count) chars), attempting to insert now")
        
        // Store locally for retry attempts
        pendingTranscript = transcript
        transcriptInsertionAttempts = 0
        
        // Stop polling since we got the transcript
        stopTranscriptPolling()
        
        // Try to insert with retries
        tryInsertTranscriptWithRetries(transcript)
    }
    
    private func tryInsertTranscriptWithRetries(_ transcript: String) {
        transcriptInsertionAttempts += 1
        
        // Try multiple times with delays to ensure keyboard is ready
        let delays: [TimeInterval] = [0.0, 0.1, 0.3, 0.5, 1.0, 2.0]
        
        guard transcriptInsertionAttempts <= delays.count else {
            logger.warning("⚠️ Keyboard: Max insertion attempts (\(delays.count)) reached, giving up")
            // Consume the transcript even if we failed (to prevent it from being stuck)
            _ = coordinator.getAndConsumeTranscript(afterTimestamp: stopRequestTimestamp)
            pendingTranscript = nil
            transcriptInsertionAttempts = 0
            return
        }
        
        let delay = delays[transcriptInsertionAttempts - 1]
        logger.info("🔄 Keyboard: Attempt \(transcriptInsertionAttempts)/\(delays.count), delay: \(delay)s")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            
            // textDocumentProxy should always be available in KeyboardInputViewController
            // But we can check if the view is in a window as a proxy for keyboard readiness
            guard self.view.window != nil else {
                if delay < delays.last! {
                    // Retry if we haven't exhausted all attempts
                    self.logger.debug("⏳ Keyboard: View not in window yet, will retry")
                    self.tryInsertTranscriptWithRetries(transcript)
                } else {
                    self.logger.warning("❌ Keyboard: View never appeared in window")
                    // Consume the transcript to prevent it from being stuck
                    _ = self.coordinator.getAndConsumeTranscript(afterTimestamp: self.stopRequestTimestamp)
                    self.pendingTranscript = nil
                }
                return
            }
            
            // Try to insert
            self.logger.info("📝 Keyboard: Attempting insertion (attempt \(self.transcriptInsertionAttempts)/\(delays.count))")
            let success = self.insertTranscript(transcript)
            
            if success {
                // Success! Consume the transcript
                self.logger.info("✅ Keyboard: Successfully inserted transcript on attempt \(self.transcriptInsertionAttempts)")
                _ = self.coordinator.getAndConsumeTranscript(afterTimestamp: self.stopRequestTimestamp)
                self.pendingTranscript = nil
                self.transcriptInsertionAttempts = 0
            } else if self.transcriptInsertionAttempts < delays.count {
                // Failed but have more attempts - retry
                self.logger.warning("⚠️ Keyboard: Insertion returned false, will retry (attempt \(self.transcriptInsertionAttempts)/\(delays.count))")
                self.tryInsertTranscriptWithRetries(transcript)
            } else {
                // All attempts exhausted
                self.logger.error("❌ Keyboard: All \(delays.count) insertion attempts failed")
                // Consume the transcript to prevent it from being stuck
                _ = self.coordinator.getAndConsumeTranscript(afterTimestamp: self.stopRequestTimestamp)
                self.pendingTranscript = nil
                self.transcriptInsertionAttempts = 0
            }
        }
    }
    
    private func setupTranscriptNotificationObserver() {
        // Listen for Darwin notifications about transcript being ready
        let notificationName = "com.prakashjoshipax.VoiceInk.transcriptReady"
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { (center, observer, name, object, userInfo) in
                guard let observer = observer else { return }
                let keyboardVC = Unmanaged<KeyboardViewController>.fromOpaque(observer).takeUnretainedValue()
                keyboardVC.handleTranscriptReadyNotification()
            },
            notificationName as CFString,
            nil,
            .deliverImmediately
        )
        
        logger.info("📡 Keyboard: Set up transcript ready notification observer")
    }
    
    private func handleTranscriptReadyNotification() {
        logger.info("🔔 Keyboard: Received transcript ready Darwin notification")
        
        // Try to insert immediately when we get the notification
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.coordinator.isTranscriptReady {
                self.logger.info("✅ Keyboard: Transcript is ready (from notification), attempting insertion")
                // Always try immediate insertion when we get the notification
                // This ensures we catch it as soon as possible
                self.attemptTranscriptInsertion()
            } else {
                self.logger.warning("⚠️ Keyboard: Notification received but transcript not ready yet")
            }
        }
    }
    
    private func tryInsertPendingTranscript() {
        guard coordinator.isTranscriptReady else { return }
        
        // Be more aggressive - try to insert even if keyboard doesn't seem fully ready
        logger.info("🔄 Keyboard: Attempting to insert pending transcript")
        attemptTranscriptInsertion()
    }
    
    private func insertTranscript(_ text: String) -> Bool {
        // Insert the text at the current cursor position
        logger.info("📝 Keyboard: Attempting to insert transcript: \(text.prefix(50))... (length: \(text.count))")
        
        // textDocumentProxy is always available in KeyboardInputViewController
        let proxy = textDocumentProxy
        logger.debug("📝 Keyboard: textDocumentProxy available, hasText=\(proxy.hasText)")
        
        // Use textDocumentProxy.insertText directly - this is the standard iOS keyboard extension API
        // For reliability, always insert in smaller chunks
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        guard !words.isEmpty else {
            logger.warning("⚠️ Keyboard: No words to insert")
            return false
        }
        
        // If text is short, insert all at once for better performance
        if text.count < 100 {
            logger.info("📝 Keyboard: Inserting short text all at once")
            proxy.insertText(text)
            logger.info("✅ Keyboard: Text inserted successfully")
            
            // Provide haptic feedback
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.success)
            return true
        }
        
        // For longer text, insert word by word
        var wordIndex = 0
        
        func insertNextWord() {
            guard wordIndex < words.count else {
                logger.info("✅ Keyboard: Finished inserting all \(words.count) words")
                
                // Provide haptic feedback
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)
                return
            }
            
            let word = words[wordIndex]
            // Add space before word (except first word)
            let prefix = wordIndex > 0 ? " " : ""
            let textToInsert = prefix + word
            
            // Insert the word
            proxy.insertText(textToInsert)
            
            wordIndex += 1
            
            // Insert next word after a small delay to ensure reliability
            if wordIndex < words.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    insertNextWord()
                }
            } else {
                logger.info("✅ Keyboard: All text inserted successfully (\(words.count) words)")
                
                // Provide haptic feedback
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)
            }
        }
        
        // Start inserting
        insertNextWord()
        
        // Return success (note: for async word-by-word insertion, this is optimistic)
        // The actual success will be determined by whether all words were inserted
        return true
    }
    
    private func updateButtonAppearanceBasedOnState() {
        let isRecording = coordinator.isRecording
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.recordButton else { return }
            
            if isRecording {
                // Configure for recording state
                logger.debug("🎙️ Keyboard: Updating button to recording state (Stop)")
                self.configureButtonForRecordingState()
            } else {
                // Configure for idle state
                logger.debug("🎙️ Keyboard: Updating button to idle state (Record)")
                self.configureButtonForIdleState()
                // Stop transcript polling if recording stopped (user might have stopped from app)
                self.stopTranscriptPolling()
            }
            
            // Ensure capsule shape is maintained
            button.layer.cornerRadius = button.frame.height / 2
        }
    }
    
    override func textWillChange(_ textInput: UITextInput?) {
        // The app is about to change the document's contents
        super.textWillChange(textInput)
    }
    
    override func textDidChange(_ textInput: UITextInput?) {
        // The app has just changed the document's contents
        super.textDidChange(textInput)
        
        // Check if there's a pending transcript when text field becomes active
        // This ensures we insert transcript even if keyboard wasn't active when it was ready
        if coordinator.isTranscriptReady {
            logger.info("📝 Keyboard: Text field changed and transcript is ready, attempting to insert")
            // Try immediately - use the more aggressive insertion method
            attemptTranscriptInsertion()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Stop polling when keyboard disappears
        stopTranscriptPolling()
        // Note: We keep the recording status timer running so it can update
        // when the keyboard appears again
    }
}
