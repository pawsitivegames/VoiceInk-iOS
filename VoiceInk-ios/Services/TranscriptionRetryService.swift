//
//  TranscriptionRetryService.swift
//  VoiceInk-ios
//
//  Created by Taafa D on 12/08/2025.
//

import Foundation
import SwiftData

class TranscriptionRetryService {
    private let postProcessor = LLMPostProcessor()
    private let translationService = TranslationService.shared
    private let languageDetectionService = LanguageDetectionService.shared
    
    static let shared = TranscriptionRetryService()
    
    private init() {}
    
    /// Retranslates all existing notes with the new language configuration
    /// Only retranslates notes that have completed transcriptions
    @MainActor
    func retranslateAllNotes(modelContext: ModelContext) async {
        Logger.info("Starting retranslation of all notes with new language configuration", category: "TranscriptionRetryService")
        
        do {
            // Fetch all notes with completed transcriptions
            let completedStatus = TranscriptionStatus.completed
            let descriptor = FetchDescriptor<Transcription>(
                predicate: #Predicate<Transcription> { note in
                    note.transcriptionStatus == completedStatus
                },
                sortBy: [SortDescriptor(\Transcription.timestamp, order: .forward)]
            )
            
            let notes = try modelContext.fetch(descriptor)
            Logger.info("Found \(notes.count) notes to retranslate", category: "TranscriptionRetryService")
            
            var successCount = 0
            var failureCount = 0
            
            // Retranslate each note in batches for better performance and UI updates
            let batchSize = 5
            for (index, note) in notes.enumerated() {
                // Get the text to translate (enhanced text if available, otherwise original text)
                let textToTranslate = note.enhancedText ?? note.text
                
                guard !textToTranslate.isEmpty else {
                    Logger.warning("Skipping note with empty text", category: "TranscriptionRetryService")
                    continue
                }
                
                do {
                    let settings = AppSettings.shared
                    let langConfig = settings.languageConfiguration
                    
                    // Determine source and target languages
                    let detectedLang = note.detectedLanguage ?? langConfig.sourceLanguageCode
                    let oppositeCode = langConfig.oppositeLanguageCode(for: detectedLang)
                    
                    // Translate using new language configuration
                    let translatedText = try await translationService.translate(
                        text: textToTranslate,
                        from: detectedLang,
                        to: oppositeCode
                    )
                    
                    // Update note with new translation and target language code
                    note.translatedText = translatedText
                    note.translatedLanguageCode = oppositeCode
                    successCount += 1
                    
                    Logger.debug("Retranslated note \(note.id) from \(detectedLang) to \(oppositeCode)", category: "TranscriptionRetryService")
                    
                    // Save in batches to ensure UI updates without being too slow
                    if (index + 1) % batchSize == 0 || index == notes.count - 1 {
                        modelContext.processPendingChanges()
                        try modelContext.save()
                        Logger.debug("Saved batch of retranslations (processed \(index + 1) of \(notes.count))", category: "TranscriptionRetryService")
                    }
                } catch {
                    Logger.error("Failed to retranslate note \(note.id): \(error.localizedDescription)", category: "TranscriptionRetryService")
                    failureCount += 1
                    // Continue with other notes even if one fails
                }
            }
            
            // Final save to ensure all changes are persisted
            modelContext.processPendingChanges()
            try modelContext.save()
            
            Logger.info("Retranslation complete: \(successCount) succeeded, \(failureCount) failed", category: "TranscriptionRetryService")
        } catch {
            Logger.error("Failed to fetch notes for retranslation: \(error.localizedDescription)", category: "TranscriptionRetryService")
        }
    }
    
    /// Retries transcription for a given note using current app settings
    func retranscribe(note: Transcription) async throws -> String {
        guard let audioPath = note.fullAudioPath,
              FileManager.default.fileExists(atPath: audioPath) else {
            throw TranscriptionError.audioFileNotFound
        }
        
        let settings = AppSettings.shared
        let provider = settings.effectiveTranscriptionProvider
        let apiKey = settings.apiKey(for: provider)
        let model = settings.effectiveTranscriptionModel
        
        guard !apiKey.isEmpty else {
            throw TranscriptionError.noApiKey
        }
        
        let fileURL = URL(fileURLWithPath: audioPath)
        let transcriptionService = TranscriptionServiceFactory.service(for: provider)
        let rawText = try await transcriptionService.transcribeAudioFile(
            apiBaseURL: provider.baseURL,
            apiKey: apiKey,
            model: model,
            fileURL: fileURL,
            language: nil
        )
        
        // PERFORMANCE: Clean up transcription using pre-compiled regex patterns
        // This reuses the optimized cleaning function from TextCleaningService
        let cleanedText = TextCleaningService.cleanTranscriptionText(rawText)
        
        // Detect language early to apply transcription correction if needed
        let preliminaryLanguage = languageDetectionService.detectLanguage(from: cleanedText)
        Logger.debug("Preliminary language detection: \(preliminaryLanguage ?? "en (default)")", category: "TranscriptionRetryService")
        
        var finalText = cleanedText
        let langConfig = settings.languageConfiguration
        
        // Automatic transcription correction for better accuracy with accents (runs before user's post-processing)
        // Only apply if detected language matches target language (user is practicing target language)
        let detectedLangCode = preliminaryLanguage ?? langConfig.sourceLanguageCode
        if detectedLangCode == langConfig.targetLanguageCode && !cleanedText.isEmpty {
            Logger.debug("\(LanguageHelper.languageName(for: detectedLangCode)) detected - applying automatic correction for better accuracy", category: "TranscriptionRetryService")
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
                    Logger.info("\(LanguageHelper.languageName(for: detectedLangCode)) transcription corrected successfully", category: "TranscriptionRetryService")
                } catch {
                    Logger.warning("Transcription correction failed: \(error.localizedDescription), using original transcription", category: "TranscriptionRetryService")
                    // Continue with original text if correction fails
                    finalText = cleanedText
                }
            } else {
                Logger.warning("No API key for transcription correction, skipping automatic correction", category: "TranscriptionRetryService")
            }
        }
        
        // Optional user-configured post-processing (runs after transcription correction if applicable)
        var postProcessingError: String? = nil
        if settings.effectiveIsPostProcessingEnabled {
            let ppPrompt = settings.effectiveCustomPrompt
            if !ppPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let llmProvider = settings.effectivePostProcessingProvider
                let llmKey = settings.apiKey(for: llmProvider)
                let llmModel = settings.effectivePostProcessingModel
                if !llmKey.isEmpty {
                    do {
                        // Use corrected text if available, otherwise use cleaned text
                        let textToProcess = finalText
                        finalText = try await postProcessor.postProcessTranscript(
                            provider: llmProvider,
                            apiKey: llmKey,
                            model: llmModel,
                            prompt: ppPrompt,
                            transcript: textToProcess
                        )
                    } catch {
                        // Post-processing failed, but transcription succeeded
                        postProcessingError = "Post-processing failed: \(error.localizedDescription)"
                        // finalText already contains Spanish-corrected text (if applied) or cleaned text, so no need to reassign
                    }
                }
            }
        }
        
        // Final language detection (after all processing)
        let detectedLanguage = languageDetectionService.detectLanguage(from: finalText)
        // detectLanguage only returns "en" or "es" (or nil, which defaults to English)
        Logger.debug("Detected language: \(detectedLanguage ?? "en (default)")", category: "TranscriptionRetryService")
        
        // Translate based on detected language and language configuration
        var translatedText: String? = nil
        var translatedLanguageCode: String? = nil
        if !finalText.isEmpty {
            do {
                let detectedLang = detectedLanguage ?? langConfig.sourceLanguageCode
                let oppositeCode = langConfig.oppositeLanguageCode(for: detectedLang)
                translatedText = try await translationService.translate(
                    text: finalText,
                    from: detectedLang,
                    to: oppositeCode
                )
                translatedLanguageCode = oppositeCode
            } catch {
                // Translation failed, but don't fail the whole retranscription
                Logger.warning("Translation failed: \(error.localizedDescription)", category: "TranscriptionRetryService")
            }
        }
        
        // Update note
        note.text = cleanedText
        note.enhancedText = (finalText == cleanedText) ? nil : finalText
        note.translatedText = translatedText
        note.translatedLanguageCode = translatedLanguageCode
        note.detectedLanguage = detectedLanguage
        note.transcriptionModelName = model
        if settings.effectiveIsPostProcessingEnabled {
            note.aiEnhancementModelName = settings.effectivePostProcessingModel
        }
        note.transcriptionStatus = .completed
        note.transcriptionError = postProcessingError
        
        return finalText
    }
    
}

enum TranscriptionError: LocalizedError {
    case audioFileNotFound
    case noApiKey
    
    var errorDescription: String? {
        switch self {
        case .audioFileNotFound:
            return "Audio file not found"
        case .noApiKey:
            return "No API key configured"
        }
    }
}
