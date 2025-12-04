//
//  WhisperTranscriptionService.swift
//  VoiceInk-ios
//
//  Local transcription service using Whisper.cpp
//

import Foundation

enum WhisperTranscriptionError: Error {
    case noModelAvailable
    case modelLoadFailed
    case audioProcessingFailed
    case transcriptionFailed
    
    var localizedDescription: String {
        switch self {
        case .noModelAvailable:
            return "No local Whisper model is available. Please download a model first."
        case .modelLoadFailed:
            return "Failed to load the Whisper model."
        case .audioProcessingFailed:
            return "Failed to process audio file for transcription."
        case .transcriptionFailed:
            return "Whisper transcription failed."
        }
    }
}

struct WhisperTranscriptionService: TranscriptionService {
    
    /// Transcribe audio file using local Whisper model
    /// Only supports "en" (English) and "es" (Spanish) languages
    func transcribeAudioFile(
        apiBaseURL: URL,
        apiKey: String,
        model: String,
        fileURL: URL,
        language: String? = nil
    ) async throws -> String {
        
        // Validate language parameter - only allow "en" or "es"
        var validatedLanguage: String? = nil
        if let lang = language {
            if lang == "en" || lang == "es" {
                validatedLanguage = lang
                Logger.debug("Using specified language: \(lang)", category: "WhisperTranscriptionService")
            } else {
                Logger.warning("Invalid language '\(lang)', only 'en' and 'es' are supported. Using auto-detection instead.", category: "WhisperTranscriptionService")
                validatedLanguage = nil
            }
        }
        
        Logger.debug("Starting local transcription", category: "WhisperTranscriptionService")
        
        // Get available model
        let modelManager = LocalModelManager.shared
        guard let modelPath = await modelManager.baseModelPath else {
            throw WhisperTranscriptionError.noModelAvailable
        }
        
        Logger.debug("Using model at \(modelPath)", category: "WhisperTranscriptionService")
        
        // Load Whisper context
        let context: WhisperContext
        do {
            context = try await WhisperContext.createContext(path: modelPath)
            // Note: If you see a warning about Core ML encoder model not found, this is expected.
            // The Core ML encoder is an optional optimization - the library falls back to CPU automatically.
        } catch {
            Logger.error("Failed to load model: \(error.localizedDescription)", category: "WhisperTranscriptionService")
            throw WhisperTranscriptionError.modelLoadFailed
        }
        
        // Process audio file (expecting WAV format from recorder)
        // PERFORMANCE: Uses async file reading to avoid blocking
        let audioSamples: [Float]
        do {
            audioSamples = try await decodeWaveFile(fileURL)
            Logger.debug("Processed \(audioSamples.count) audio samples", category: "WhisperTranscriptionService")
        } catch {
            Logger.error("Audio processing failed: \(error.localizedDescription)", category: "WhisperTranscriptionService")
            // Clean up resources before throwing
            await context.releaseResources()
            throw WhisperTranscriptionError.audioProcessingFailed
        }
        
        // Perform transcription with language parameter (nil for auto-detection)
        // Only "en" or "es" are allowed - validatedLanguage is already filtered
        let success = await context.fullTranscribe(samples: audioSamples, language: validatedLanguage)
        
        if success {
            let transcription = await context.getTranscription()
            
            // Get detected language if auto-detection was used
            // getDetectedLanguage() only returns "en" or "es" (or nil)
            let detectedLanguage = await context.getDetectedLanguage()
            if let detected = detectedLanguage {
                Logger.debug("Detected language: \(detected) (English/Spanish only)", category: "WhisperTranscriptionService")
            } else if validatedLanguage != nil {
                Logger.debug("Used specified language: \(validatedLanguage!)", category: "WhisperTranscriptionService")
            } else {
                Logger.debug("Language detection unavailable or detected non-English/Spanish language", category: "WhisperTranscriptionService")
            }
            
            // Clean up resources
            await context.releaseResources()
            Logger.info("Transcription completed successfully", category: "WhisperTranscriptionService")
            return transcription.isEmpty ? "No audio detected." : transcription
        } else {
            // Clean up resources before throwing error
            await context.releaseResources()
            Logger.error("Transcription failed", category: "WhisperTranscriptionService")
            throw WhisperTranscriptionError.transcriptionFailed
        }
    }
    
    /// Verify API key (not applicable for local transcription, always returns true if model is available)
    func verifyAPIKey(apiBaseURL: URL, _ apiKey: String) async -> Bool {
        let modelManager = LocalModelManager.shared
        return await modelManager.hasAvailableModel
    }
}

// MARK: - Convenience Extensions

extension WhisperTranscriptionService {
    
    /// Transcribe audio with simplified parameters for local use
    func transcribeAudioFile(_ fileURL: URL) async throws -> String {
        // Use dummy values for parameters that don't apply to local transcription
        return try await transcribeAudioFile(
            apiBaseURL: URL(string: "http://localhost")!,
            apiKey: "local",
            model: "base.en",
            fileURL: fileURL,
            language: "en"
        )
    }
    
    /// Check if local transcription is available
    @MainActor
    static var isAvailable: Bool {
        LocalModelManager.shared.hasAvailableModel
    }
    
    /// Get status information for UI display
    @MainActor
    static func getStatusInfo() -> (isAvailable: Bool, modelInfo: String?) {
        let modelManager = LocalModelManager.shared
        
        if let model = modelManager.firstAvailableModel {
            return (true, "\(model.displayName) (\(model.size))")
        } else {
            return (false, "No model downloaded")
        }
    }
}
