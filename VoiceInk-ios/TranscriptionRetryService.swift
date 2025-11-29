//
//  TranscriptionRetryService.swift
//  VoiceInk-ios
//
//  Created by Taafa D on 12/08/2025.
//

import Foundation

class TranscriptionRetryService {
    private let postProcessor = LLMPostProcessor()
    private let translationService = TranslationService()
    
    static let shared = TranscriptionRetryService()
    
    private init() {}
    
    /// Retries transcription for a given note using current app settings
    func retranscribe(note: Transcription) async throws -> String {
        guard let audioPath = note.fullAudioPath,
              FileManager.default.fileExists(atPath: audioPath) else {
            throw TranscriptionError.audioFileNotFound
        }
        
        let settings = AppSettings.shared
        let provider = await settings.effectiveTranscriptionProvider
        let apiKey = await settings.apiKey(for: provider)
        let model = await settings.effectiveTranscriptionModel
        
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
        // This reuses the optimized cleaning function from RecordingManager
        let cleanedText = RecordingManager.cleanTranscriptionText(rawText)
        
        // Detect language early to apply Spanish correction if needed
        let preliminaryLanguage = detectLanguage(from: cleanedText)
        Logger.debug("Preliminary language detection: \(preliminaryLanguage ?? "en (default)")", category: "TranscriptionRetryService")
        
        var finalText = cleanedText
        
        // Automatic Spanish correction for better accuracy with accents (runs before user's post-processing)
        if preliminaryLanguage == "es" && !cleanedText.isEmpty {
            Logger.debug("Spanish detected - applying automatic correction for better accuracy", category: "TranscriptionRetryService")
            let llmProvider = await settings.effectivePostProcessingProvider
            let llmKey = await settings.apiKey(for: llmProvider)
            let llmModel = await settings.effectivePostProcessingModel
            
            if !llmKey.isEmpty {
                do {
                    let correctedText = try await postProcessor.correctSpanishTranscription(
                        provider: llmProvider,
                        apiKey: llmKey,
                        model: llmModel,
                        transcript: cleanedText
                    )
                    finalText = correctedText
                    Logger.info("Spanish transcription corrected successfully", category: "TranscriptionRetryService")
                } catch {
                    Logger.warning("Spanish correction failed: \(error.localizedDescription), using original transcription", category: "TranscriptionRetryService")
                    // Continue with original text if correction fails
                    finalText = cleanedText
                }
            } else {
                Logger.warning("No API key for Spanish correction, skipping automatic correction", category: "TranscriptionRetryService")
            }
        }
        
        // Optional user-configured post-processing (runs after Spanish correction if applicable)
        var postProcessingError: String? = nil
        if await settings.effectiveIsPostProcessingEnabled {
            let ppPrompt = await settings.effectiveCustomPrompt
            if !ppPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let llmProvider = await settings.effectivePostProcessingProvider
                let llmKey = await settings.apiKey(for: llmProvider)
                let llmModel = await settings.effectivePostProcessingModel
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
        let detectedLanguage = detectLanguage(from: finalText)
        // detectLanguage only returns "en" or "es" (or nil, which defaults to English)
        Logger.debug("Detected language: \(detectedLanguage ?? "en (default)")", category: "TranscriptionRetryService")
        
        // Translate based on detected language (only English↔Spanish translation supported)
        var translatedText: String? = nil
        if !finalText.isEmpty {
            do {
                if detectedLanguage == "es" {
                    // Spanish input → translate to English
                    translatedText = try await translationService.translateToEnglish(text: finalText)
                } else {
                    // English input (or undetected/nil) → translate to Spanish (default behavior)
                    // Only English and Spanish are supported - any other language defaults to English
                    translatedText = try await translationService.translateToSpanish(text: finalText)
                }
            } catch {
                // Translation failed, but don't fail the whole retranscription
                Logger.warning("Translation failed: \(error.localizedDescription)", category: "TranscriptionRetryService")
            }
        }
        
        // Update note
        note.text = cleanedText
        note.enhancedText = (finalText == cleanedText) ? nil : finalText
        note.translatedText = translatedText
        note.detectedLanguage = detectedLanguage
        note.transcriptionModelName = model
        if await settings.effectiveIsPostProcessingEnabled {
            note.aiEnhancementModelName = await settings.effectivePostProcessingModel
        }
        note.transcriptionStatus = .completed
        note.transcriptionError = postProcessingError
        
        return finalText
    }
    
    // MARK: - Language Detection
    
    /// Detect language from text using simple heuristics
    /// Only supports English and Spanish - returns "es" for Spanish, "en" for English (or nil which defaults to English)
    /// Other languages are not supported and will default to English
    private func detectLanguage(from text: String) -> String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
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
        
        Logger.debug("Language detection: Spanish score: \(spanishScore), English score: \(englishScore)", category: "TranscriptionRetryService")
        
        // If Spanish score is significantly higher, return "es"
        if spanishScore > englishScore + 2 {
            return "es"
        }
        
        // If English score is higher or equal, return "en" (default)
        if englishScore >= spanishScore {
            return "en"
        }
        
        // If scores are close, default to English (existing behavior)
        return "en"
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
