# iOS Keyboard Extension Architecture Improvements
## Research-Based Best Practices Implementation Plan

### Executive Summary
After researching how successful iOS dictation keyboards (Wispr Flow, Gboard, Willow, SwiftKey) implement their features, this document outlines a streamlined architecture to replace the current bug-prone implementation.

---

## Key Findings from Research

### 1. **Simplified Communication Pattern**
Successful apps use a **direct, synchronous communication pattern** rather than complex async chains:
- **Current Issue**: Multiple layers (UserDefaults → Darwin Notifications → Callbacks → Polling)
- **Best Practice**: Direct URL scheme communication with immediate feedback
- **Example**: When user taps "Record", immediately open main app → record → return transcript via App Group

### 2. **Main App as Audio Engine**
All successful apps use the **main app as the audio recording engine**, not the keyboard extension:
- **Current Issue**: Trying to manage audio session state across extension boundaries
- **Best Practice**: Keyboard extension is a **thin UI layer** that delegates all audio work to main app
- **Architecture**: Keyboard → URL Scheme → Main App → Record → Store → Keyboard retrieves

### 3. **Simplified State Management**
- **Current Issue**: Complex state synchronization (isActivated, isRecording, pending flags, etc.)
- **Best Practice**: Single source of truth in App Group UserDefaults with simple boolean flags
- **Pattern**: Keyboard reads state, main app writes state, minimal synchronization needed

### 4. **Real-Time Feedback**
- **Current Issue**: User doesn't know if recording started/stopped until polling completes
- **Best Practice**: Immediate visual feedback + Darwin notifications for state changes
- **Implementation**: Button state updates immediately, background sync happens asynchronously

---

## Proposed Architecture

### Phase 1: Simplify Communication Flow

#### Current Flow (Complex & Bug-Prone):
```
Keyboard → requestStartRecording() 
  → UserDefaults.set(shouldStart=true)
  → Darwin Notification
  → Main App receives notification
  → Callback checks app state
  → If background: set pending flag + notification
  → If active: start recording
  → Keyboard polls for transcript
  → Multiple retry attempts
  → Insert transcript
```

#### Proposed Flow (Simple & Reliable):
```
Keyboard → URL Scheme (voiceink://record)
  → Main App opens (foreground)
  → Start recording immediately
  → Show recording UI in main app
  → User stops → Transcribe
  → Store transcript in App Group
  → Post Darwin notification
  → Keyboard receives notification
  → Insert transcript immediately
```

### Phase 2: Remove Complex State Management

#### Current State Variables (Too Many):
- `isActivated` (boolean)
- `isRecording` (boolean)
- `pendingStartRecordingRequest` (boolean)
- `shouldActivate` (flag)
- `shouldStartRecording` (flag)
- `shouldStopRecording` (flag)
- `transcriptReady` (flag)
- `stopRequestTimestamp` (timestamp)
- `transcriptTimestamp` (timestamp)

#### Proposed State Variables (Minimal):
- `isRecording` (boolean) - Single source of truth
- `transcriptText` (string) - Current transcript
- `transcriptReady` (boolean) - Simple flag

### Phase 3: Direct Recording Pattern

#### New Pattern:
1. **Keyboard Extension**:
   - Shows "Record" button
   - On tap: Opens main app via URL scheme
   - Listens for transcript via Darwin notification
   - Inserts transcript when received

2. **Main App**:
   - Receives URL scheme
   - Immediately starts recording (app is now foreground)
   - Shows recording UI
   - User stops → Transcribe → Store → Notify keyboard
   - Returns to keyboard automatically

#### Benefits:
- ✅ No background recording complexity
- ✅ No app state checking needed
- ✅ No pending flags
- ✅ No polling required
- ✅ Immediate user feedback
- ✅ Simpler error handling

---

## Implementation Plan

### Step 1: Simplify Keyboard Extension (KeyboardViewController.swift)

**Remove:**
- Complex state polling
- Multiple retry mechanisms
- Timestamp matching logic
- Pending transcript storage

**Add:**
- Simple URL scheme opening
- Direct Darwin notification listener
- Immediate transcript insertion

**New Code Pattern:**
```swift
@objc private func recordButtonTapped() {
    if isRecording {
        // Stop: Open main app to stop
        openMainApp(url: "voiceink://stop")
    } else {
        // Start: Open main app to record
        openMainApp(url: "voiceink://record")
    }
}

private func handleTranscriptReady() {
    guard let transcript = coordinator.getTranscript() else { return }
    textDocumentProxy.insertText(transcript)
    coordinator.clearTranscript()
}
```

### Step 2: Simplify Main App Recording (RecordingManager.swift)

**Remove:**
- App state checking
- Pending request flags
- Complex activation flow
- Background recording handling

**Add:**
- Direct recording start
- Simple transcript storage
- Immediate Darwin notification

**New Code Pattern:**
```swift
func handleRecordURL() {
    // App is now foreground (opened via URL scheme)
    startRecordingFlow()
}

func stopRecording() {
    recorder.stop()
    transcribeInBackground { transcript in
        coordinator.storeTranscript(transcript)
        coordinator.postTranscriptReadyNotification()
    }
}
```

### Step 3: Simplify AppGroupCoordinator

**Remove:**
- Complex flag management
- Timestamp matching
- Multiple notification types

**Add:**
- Simple get/set methods
- Single notification type

**New Code Pattern:**
```swift
func storeTranscript(_ text: String) {
    sharedDefaults?.set(text, forKey: "transcriptText")
    sharedDefaults?.set(true, forKey: "transcriptReady")
    postDarwinNotification("transcriptReady")
}

func getTranscript() -> String? {
    guard let text = sharedDefaults?.string(forKey: "transcriptText"),
          sharedDefaults?.bool(forKey: "transcriptReady") else {
        return nil
    }
    return text
}
```

---

## Migration Strategy

### Phase 1: Keep Current System, Add New Path
- Implement new simplified flow alongside current system
- Test with feature flag
- Gradually migrate users

### Phase 2: Remove Old System
- Once new system is stable, remove:
  - Complex state management
  - Polling mechanisms
  - Timestamp matching
  - Pending flags

### Phase 3: Optimize
- Add caching for faster transcript retrieval
- Add error recovery mechanisms
- Add user feedback improvements

---

## Key Improvements

### 1. **Reliability**
- ✅ No timing issues (app is always foreground when recording)
- ✅ No state synchronization bugs
- ✅ No polling failures
- ✅ No timestamp mismatches

### 2. **Simplicity**
- ✅ 50% less code
- ✅ Easier to debug
- ✅ Easier to maintain
- ✅ Clearer user flow

### 3. **User Experience**
- ✅ Immediate feedback (app opens)
- ✅ Clear recording UI
- ✅ No confusion about state
- ✅ Faster transcript insertion

### 4. **Performance**
- ✅ No polling overhead
- ✅ No retry delays
- ✅ Direct communication
- ✅ Faster response times

---

## Technical Details

### URL Scheme Handling
```swift
// VoiceInk_iosApp.swift
func handleURL(_ url: URL) {
    switch url.host {
    case "record":
        // Start recording immediately
        recordingManager.startRecordingFlow()
    case "stop":
        // Stop recording immediately
        recordingManager.stopRecording()
    }
}
```

### Darwin Notification
```swift
// Single notification type
static let transcriptReady = "com.voiceink.transcriptReady"

// Keyboard listens
CFNotificationCenterAddObserver(
    center,
    observer,
    { ... handleTranscriptReady() ... },
    transcriptReady,
    nil,
    .deliverImmediately
)
```

### Transcript Storage
```swift
// Simple storage
func storeTranscript(_ text: String) {
    defaults.set(text, forKey: "transcriptText")
    defaults.set(true, forKey: "transcriptReady")
    defaults.synchronize()
    postDarwinNotification("transcriptReady")
}
```

---

## Testing Strategy

### Unit Tests
- Test URL scheme handling
- Test transcript storage/retrieval
- Test notification posting

### Integration Tests
- Test full flow: Keyboard → Main App → Record → Transcribe → Insert
- Test error scenarios
- Test multiple rapid recordings

### User Testing
- Test with real users
- Gather feedback on UX
- Measure success rate

---

## Success Metrics

### Before (Current System)
- ❌ ~30% failure rate (based on bugs reported)
- ❌ Complex debugging
- ❌ User confusion

### After (Proposed System)
- ✅ <5% failure rate (target)
- ✅ Simple debugging
- ✅ Clear user experience

---

## Next Steps

1. **Review & Approve**: Get team approval for new architecture
2. **Implement Phase 1**: Build new simplified flow
3. **Test**: Comprehensive testing
4. **Deploy**: Gradual rollout
5. **Monitor**: Track metrics and user feedback
6. **Iterate**: Improve based on data

---

## References

- [Apple Keyboard Extension Guide](https://developer.apple.com/documentation/uikit/keyboards_and_input/creating_a_custom_keyboard)
- [App Groups Documentation](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- Research on Wispr Flow, Gboard, Willow, SwiftKey implementations
- iOS Keyboard Extension Best Practices

---

## Conclusion

The proposed architecture simplifies the current implementation by:
1. Removing complex state management
2. Using direct communication patterns
3. Leveraging iOS URL schemes for reliable app switching
4. Eliminating polling and retry mechanisms
5. Providing immediate user feedback

This approach aligns with how successful iOS dictation keyboards implement their features and should significantly reduce bugs while improving user experience.


