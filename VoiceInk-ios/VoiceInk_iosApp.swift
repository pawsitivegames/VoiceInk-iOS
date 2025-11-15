//
//  VoiceInk_iosApp.swift
//  VoiceInk-ios
//
//  Created by Prakash Joshi on 12/08/2025.
//

import SwiftUI
import SwiftData

@main
struct VoiceInk_iosApp: App {
    @State private var hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @StateObject private var recordingManager = RecordingManager()
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Clear any stale recording state on app launch
        AppGroupCoordinator.shared.updateRecordingState(false)
        print("🧹 Cleared stale recording state on app launch")
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Transcription.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
                    .environmentObject(recordingManager)
                    .onOpenURL { url in
                        handleURL(url)
                    }
                    .onChange(of: scenePhase) { oldPhase, newPhase in
                        handleScenePhaseChange(from: oldPhase, to: newPhase)
                    }
            } else {
                OnboardingView(isOnboardingComplete: $hasCompletedOnboarding)
                    .onOpenURL { url in
                        handleURL(url)
                    }
            }
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        // When app becomes active, check for stop recording flag
        if newPhase == .active && oldPhase != .active {
            print("📱 App became active, checking for stop recording flag")
            let coordinator = AppGroupCoordinator.shared
            if coordinator.checkAndConsumeStopRecordingFlag() {
                print("🛑 Stop recording flag found, stopping recording")
                if recordingManager.isRecording {
                    // We need modelContext, so post a notification
                    NotificationCenter.default.post(name: .stopRecordingFromKeyboard, object: nil)
                }
            }
        }
    }
    
    private func handleURL(_ url: URL) {
        guard url.scheme == "voiceink" else { return }
        
        switch url.host {
        case "record":
            print("🔗 URL scheme triggered: open app for recording")
            // Automatically start recording flow when opened from keyboard
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.recordingManager.startRecordingFlow()
            }
            print("📱 App opened via keyboard extension - starting recording")
        default:
            break
        }
    }
}
