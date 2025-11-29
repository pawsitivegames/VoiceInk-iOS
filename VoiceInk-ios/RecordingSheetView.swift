import SwiftUI
import UIKit

struct RecordingSheetView: View {
    @ObservedObject var recordingManager: RecordingManager
    @ObservedObject var settings: AppSettings
    let onCancel: () -> Void
    let onStop: () -> Void
    
    private var languageHintText: String {
        let sourceName = LanguageHelper.languageName(for: settings.languageConfiguration.sourceLanguageCode)
        let targetName = LanguageHelper.languageName(for: settings.languageConfiguration.targetLanguageCode)
        return "Speak in \(sourceName) or \(targetName) to see instant translations"
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Button("Cancel", action: onCancel)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Cancel recording")
                    .accessibilityHint("Double tap to cancel and discard this recording")
                Spacer()
                Text(recordingManager.currentDuration.formattedTimeString)
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: recordingManager.currentDuration)
                    .accessibilityLabel("Recording duration: \(recordingManager.currentDuration.formattedTimeString)")
            }
            .padding(.top, 12)

            // Language Learning Hint
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.orange)
                Text(languageHintText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Hint: \(languageHintText)")

            // Mode Picker
            VStack(spacing: 10) {
                Text("Mode")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if settings.modes.count > 1 {
                    Picker("Mode", selection: $settings.selectedModeId) {
                        ForEach(settings.modes) { mode in
                            Text(mode.name).tag(mode.id as UUID?)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 80)
                    .accessibilityLabel("Recording mode picker")
                } else if let singleMode = settings.modes.first {
                    Text(singleMode.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Recording mode: \(singleMode.name)")
                }
            }
            
            // Stop Button - Matching main button style
            Button(action: {
                // Haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                onStop()
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Stop Recording")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.red)
            .controlSize(.large)
            .shadow(color: Color.red.opacity(0.3), radius: 8, x: 0, y: 4)
            .accessibilityLabel("Stop recording")
            .accessibilityHint("Double tap to stop and save the recording")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
}

#Preview {
    RecordingSheetView(
        recordingManager: RecordingManager(),
        settings: AppSettings.shared,
        onCancel: {},
        onStop: {}
    )
}
