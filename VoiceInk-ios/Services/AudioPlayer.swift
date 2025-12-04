import Foundation
import AVFoundation
import Combine

@MainActor
final class AudioPlayer: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isLoading: Bool = false
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    
    func loadAudio(from path: String) {
        isLoading = true
        
        // CRITICAL: Clear any previous failed player to prevent "invalid reuse after initialization failure"
        audioPlayer = nil
        
        let url = URL(fileURLWithPath: path)
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            // Verify player was created successfully
            guard let player = audioPlayer else {
                Logger.error("AVAudioPlayer instance is nil after creation", category: "AudioPlayer")
                isLoading = false
                return
            }
            
            // Prepare to play - if this fails, the player might be in an invalid state
            guard player.prepareToPlay() else {
                Logger.error("Failed to prepare AVAudioPlayer for playback", category: "AudioPlayer")
                // Clear failed player to prevent reuse
                audioPlayer = nil
                isLoading = false
                return
            }
            
            duration = player.duration
            currentTime = 0
            isLoading = false
        } catch {
            Logger.error("Failed to load audio: \(error.localizedDescription)", category: "AudioPlayer")
            // CRITICAL: Clear failed player to prevent "invalid reuse after initialization failure"
            audioPlayer = nil
            isLoading = false
        }
    }
    
    func play() {
        guard let player = audioPlayer else { return }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            
            player.play()
            isPlaying = true
            startTimer()
        } catch {
            Logger.error("Failed to play audio: \(error.localizedDescription)", category: "AudioPlayer")
        }
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        currentTime = 0
        isPlaying = false
        stopTimer()
    }
    
    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }
    
    private func startTimer() {
        // Optimized timer: use RunLoop.main for proper scheduling and ensure cleanup
        timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let player = self.audioPlayer else { return }
                self.currentTime = player.currentTime
                
                if !player.isPlaying && self.isPlaying {
                    // Playback finished
                    self.isPlaying = false
                    self.timer?.invalidate()
                    self.timer = nil
                }
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    deinit {
        timer?.invalidate()
        timer = nil
    }
}