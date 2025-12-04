//
//  TranscriptionOrchestrator.swift
//  VoiceInk-ios
//
//  Transcription orchestration service extracted from RecordingManager
//  Follows Single Responsibility Principle - handles transcription/translation workflow
//

import Foundation
import SwiftData

/// Orchestrates the complete transcription and translation workflow
/// Extracted from RecordingManager to improve separation of concerns
@MainActor
class TranscriptionOrchestrator {
    private let transcriptionServiceFactory = TranscriptionServiceFactory.self
    private let translationService = TranslationService.shared
    private let postProcessor = LLMPostProcessor()
    private let languageDetectionService = LanguageDetectionService.shared
    private let settings = AppSettings.shared
    private let coordinator = AppGroupCoordinator.shared
    
    init() {
        // Private dependencies initialized
    }
    
    /// Process a recording through the complete transcription and translation workflow
    /// - Parameters:
    ///   - note: The Transcription note to process (will be updated in place)
    ///   - audioFileName: Name of the audio file to transcribe
    ///   - recordingDuration: Duration of the recording
    ///   - modelContext: SwiftData model context for saving
    ///   - shouldStoreTranscript: Whether to store transcript for keyboard extension
    ///   - onComplete: Callback when processing completes successfully
    ///   - onError: Callback when processing fails
    func processRecording(
        note: Transcription,
        audioFileName: String,
        recordingDuration: Double,
        modelContext: ModelContext,
        shouldStoreTranscript: Bool = false,
        onComplete: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) async {
        Logger.debug("TranscriptionOrchestrator: processRecording() called - audioFileName: \(audioFileName), duration: \(recordingDuration)s, shouldStoreTranscript: \(shouldStoreTranscript)", category: "TranscriptionOrchestrator")
        
        Task {
            defer {
                // Cleanup handled by caller
            }
            
            // Use effective settings from selected mode
            let provider = settings.effectiveTranscriptionProvider
            let apiKey = settings.apiKey(for: provider)
            let model = settings.effectiveTranscriptionModel
            Logger.debug("Transcription provider: \(provider), model: \(model)", category: "TranscriptionOrchestrator")
            
            // If no API key, update note with error and insert into SwiftData
            guard !apiKey.isEmpty else {
                Logger.error("No API key configured for provider: \(provider)", category: "TranscriptionOrchestrator")
                await MainActor.run {
                    note.transcriptionStatus = .failed
                    note.transcriptionError = "No API key configured"
                    // Insert note even on error so user can see what failed
                    modelContext.insert(note)
                    modelContext.processPendingChanges()
                    try? modelContext.save()
                    onError("No API key configured")
                }
                return
            }
            
            do {
                // Resolve the relative path to absolute path for transcription
                let recordingsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Recordings")
                let fileURL = recordingsDir.appendingPathComponent(audioFileName)
                let service = transcriptionServiceFactory.service(for: provider)
                let rawText = try await service.transcribeAudioFile(apiBaseURL: provider.baseURL, apiKey: apiKey, model: model, fileURL: fileURL, language: nil)
                
                // PERFORMANCE: Clean up transcription using pre-compiled regex patterns
                // This is faster than compiling regex on each call
                let cleanedText = TextCleaningService.cleanTranscriptionText(rawText)
                
                // Auto-delete note if no audio was detected
                let isNoAudioDetected = cleanedText.isEmpty ||
                                       cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "no audio detected." ||
                                       cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "no audible content detected."
                
                if isNoAudioDetected {
                    Logger.info("No audio detected in recording, automatically deleting note", category: "TranscriptionOrchestrator")
                    await MainActor.run {
                        // Delete the note and its audio file
                        if let audioPath = note.fullAudioPath, FileManager.default.fileExists(atPath: audioPath) {
                            try? FileManager.default.removeItem(atPath: audioPath)
                        }
                        modelContext.delete(note)
                        modelContext.processPendingChanges()
                        do {
                            try modelContext.save()
                            Logger.info("Note deleted successfully (no audio detected)", category: "TranscriptionOrchestrator")
                        } catch {
                            Logger.error("Failed to delete note: \(error.localizedDescription)", category: "TranscriptionOrchestrator")
                        }
                        onError("No audio detected")
                    }
                    return // Exit early, don't process further
                }
                
                // Detect language early to apply transcription correction if needed
                let preliminaryLanguage = languageDetectionService.detectLanguage(from: cleanedText)
                Logger.debug("Preliminary language detection: \(preliminaryLanguage ?? "en (default)")", category: "TranscriptionOrchestrator")
                
                // Update note in memory (not in SwiftData yet - will be inserted when translation completes)
                await MainActor.run {
                    Logger.debug("Updating note in memory with raw transcription (length: \(cleanedText.count))", category: "TranscriptionOrchestrator")
                    
                    note.text = cleanedText
                    note.transcriptionModelName = model
                    note.transcriptionStatus = .completed
                    // Note: Not saving yet - will insert into SwiftData when translation completes
                }
                
                // PERFORMANCE OPTIMIZATION: Start translation early in parallel with enhancements
                // This allows translation to happen concurrently instead of waiting for all processing
                let detectedLanguageForTranslation = preliminaryLanguage ?? "en"
                // Capture language configuration before entering Task
                let langConfig = settings.languageConfiguration
                // Helper struct to hold translation result with language code
                struct TranslationResult {
                    let text: String
                    let targetLanguageCode: String
                }
                let translationTask: Task<TranslationResult?, Never>? = !cleanedText.isEmpty ? Task { [weak self] in
                    guard let self = self else { return nil }
                    Logger.debug("Starting early translation in parallel with enhancements", category: "TranscriptionOrchestrator")
                    do {
                        let oppositeCode = langConfig.oppositeLanguageCode(for: detectedLanguageForTranslation)
                        let translatedText = try await withThrowingTaskGroup(of: String.self) { group in
                            // Add translation task
                            group.addTask {
                                return try await self.translationService.translate(
                                    text: cleanedText,
                                    from: detectedLanguageForTranslation,
                                    to: oppositeCode
                                )
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
                        Logger.info("Early translation completed! Length: \(translatedText.count)", category: "TranscriptionOrchestrator")
                        return TranslationResult(text: translatedText, targetLanguageCode: oppositeCode)
                    } catch {
                        Logger.warning("Early translation failed: \(error.localizedDescription), will retry with enhanced text if available", category: "TranscriptionOrchestrator")
                        return nil
                    }
                } : nil
                
                // Now run enhancements in background (non-blocking) and update UI incrementally
                var enhancedText: String? = nil
                var postProcessingError: String? = nil
                var finalText = cleanedText
                
                // Automatic transcription correction for better accuracy with accents (runs before user's post-processing)
                // Only apply if detected language matches target language (user is practicing target language)
                let detectedLangCode = preliminaryLanguage ?? settings.sourceLanguageCode
                if detectedLangCode == settings.targetLanguageCode && !cleanedText.isEmpty {
                    Logger.debug("\(LanguageHelper.languageName(for: detectedLangCode)) detected - applying automatic correction in background", category: "TranscriptionOrchestrator")
                    let llmProvider = settings.effectivePostProcessingProvider
                    let llmKey = settings.apiKey(for: llmProvider)
                    let llmModel = settings.effectivePostProcessingModel
                    
                    if !llmKey.isEmpty {
                        do {
                            let correctedText = try await postProcessor.correctTranscription(
                                provider: llmProvider,
                                apiKey: llmKey,
                                model: llmModel,
                                transcript: cleanedText,
                                languageCode: detectedLangCode
                            )
                            finalText = correctedText
                            enhancedText = correctedText
                            Logger.info("\(LanguageHelper.languageName(for: detectedLangCode)) transcription corrected successfully", category: "TranscriptionOrchestrator")
                        } catch {
                            Logger.warning("Transcription correction failed: \(error.localizedDescription), using original transcription", category: "TranscriptionOrchestrator")
                            // Continue with original text if correction fails
                            finalText = cleanedText
                        }
                    } else {
                        Logger.warning("No API key for transcription correction, skipping automatic correction", category: "TranscriptionOrchestrator")
                    }
                }
                
                // Optional user-configured post-processing (runs after transcription correction if applicable)
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
                let detectedLanguage = languageDetectionService.detectLanguage(from: textToTranslate)
                // detectLanguage only returns "en" or "es" (or nil, which defaults to English)
                Logger.debug("Detected language: \(detectedLanguage ?? "en (default)")", category: "TranscriptionOrchestrator")
                
                // Capture language configuration for translation
                let langConfigForTranslation = settings.languageConfiguration
                
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
                            Logger.debug("Transcript stored for keyboard (length: \(textToStore.count))", category: "TranscriptionOrchestrator")
                        }
                    }
                    
                    // Note: Not saving yet - will insert into SwiftData when translation completes
                    Logger.debug("Note updated in memory with all enhancements", category: "TranscriptionOrchestrator")
                }
                
                // Handle translation: use early translation if available, otherwise translate enhanced text
                if !textToTranslate.isEmpty {
                    Logger.debug("Processing translation for text: '\(textToTranslate.prefix(50))...'", category: "TranscriptionOrchestrator")
                    
                    // Wait for early translation if it's still running, or start new translation with enhanced text
                    let translationResult: TranslationResult?
                    if let earlyTask = translationTask {
                        // Check if early translation completed
                        if let earlyResult = await earlyTask.value {
                            translationResult = earlyResult
                            Logger.debug("Using early translation result", category: "TranscriptionOrchestrator")
                        } else {
                            // Early translation failed or timed out, try again with enhanced text if different
                            if textToTranslate != cleanedText {
                                Logger.debug("Retrying translation with enhanced text", category: "TranscriptionOrchestrator")
                                do {
                                    let detectedLang = detectedLanguage ?? langConfigForTranslation.sourceLanguageCode
                                    let oppositeCode = langConfigForTranslation.oppositeLanguageCode(for: detectedLang)
                                    let translatedText = try await withThrowingTaskGroup(of: String.self) { group in
                                        group.addTask {
                                            return try await self.translationService.translate(
                                                text: textToTranslate,
                                                from: detectedLang,
                                                to: oppositeCode
                                            )
                                        }
                                        group.addTask {
                                            try await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
                                            throw TranslationError.translationFailed("Translation timed out after 15 seconds")
                                        }
                                        let result = try await group.next()!
                                        group.cancelAll()
                                        return result
                                    }
                                    translationResult = TranslationResult(text: translatedText, targetLanguageCode: oppositeCode)
                                } catch {
                                    Logger.error("Retry translation failed: \(error.localizedDescription)", category: "TranscriptionOrchestrator")
                                    translationResult = nil
                                }
                            } else {
                                translationResult = nil
                            }
                        }
                    } else {
                        // No early translation task, translate now
                        do {
                            let detectedLang = detectedLanguage ?? langConfigForTranslation.sourceLanguageCode
                            let oppositeCode = langConfigForTranslation.oppositeLanguageCode(for: detectedLang)
                            let translatedText = try await withThrowingTaskGroup(of: String.self) { group in
                                group.addTask {
                                    return try await self.translationService.translate(
                                        text: textToTranslate,
                                        from: detectedLang,
                                        to: oppositeCode
                                    )
                                }
                                group.addTask {
                                    try await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
                                    throw TranslationError.translationFailed("Translation timed out after 15 seconds")
                                }
                                let result = try await group.next()!
                                group.cancelAll()
                                return result
                            }
                            translationResult = TranslationResult(text: translatedText, targetLanguageCode: oppositeCode)
                        } catch {
                            Logger.error("Translation failed: \(error.localizedDescription)", category: "TranscriptionOrchestrator")
                            translationResult = nil
                        }
                    }
                    
                    // Update note with translation on main thread, then INSERT into SwiftData
                    // OPTIMIZATION: Batch all operations into a single save
                    await MainActor.run {
                        if let result = translationResult {
                            note.translatedText = result.text
                            note.translatedLanguageCode = result.targetLanguageCode
                            Logger.info("Translation completed! Length: \(result.text.count)", category: "TranscriptionOrchestrator")
                        }
                        
                        // Insert note into SwiftData (only once, when everything is ready)
                        modelContext.insert(note)
                        modelContext.processPendingChanges()
                        try? modelContext.save()
                        Logger.info("Note inserted into SwiftData", category: "TranscriptionOrchestrator")
                        
                        onComplete()
                    }
                } else {
                    // Text to translate is empty, insert note without translation
                    Logger.warning("Text to translate is empty, skipping translation", category: "TranscriptionOrchestrator")
                    await MainActor.run {
                        modelContext.insert(note)
                        modelContext.processPendingChanges()
                        try? modelContext.save()
                        
                        onComplete()
                    }
                }
                
            } catch {
                // Update note with error on main thread, then INSERT into SwiftData
                Logger.error("Transcription failed with error: \(error.localizedDescription)", category: "TranscriptionOrchestrator")
                await MainActor.run {
                    note.transcriptionStatus = .failed
                    note.transcriptionError = error.localizedDescription
                    // Insert note even on error so user can see what failed
                    modelContext.insert(note)
                    modelContext.processPendingChanges()
                    try? modelContext.save()
                    
                    // If this was stopped from keyboard and transcription failed, store error message
                    if shouldStoreTranscript {
                        let errorMessage = "Transcription failed: \(error.localizedDescription)"
                        coordinator.storeTranscript(errorMessage)
                    }
                    
                    onError(error.localizedDescription)
                }
            }
        }
    }
}

