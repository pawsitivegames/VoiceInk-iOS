import Foundation

struct LLMPostProcessor {
    private let client = OpenAICompatibleClient()

    func postProcessTranscript(provider: Provider, apiKey: String, model: String, prompt: String, transcript: String) async throws -> String {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return transcript }
        let systemPrompt = "You are a helpful assistant that rewrites raw speech-to-text transcripts to be concise, well-punctuated, and readable notes, preserving meaning."
        let contentPrompt = "Prompt: \(prompt)\n\nTranscript:\n\(transcript)"
        let messages = [
            OAChatMessage(role: "system", content: systemPrompt),
            OAChatMessage(role: "user", content: contentPrompt)
        ]
        
        let result = try await client.chatCompletion(baseURL: provider.baseURL, apiKey: apiKey, model: model, messages: messages, temperature: 0.2)
        return result.isEmpty ? transcript : result
    }
    
    /// Automatically correct transcription errors for a specific language, especially for non-native speakers with accents
    /// This helps improve accuracy when pronunciation isn't perfect
    func correctTranscription(provider: Provider, apiKey: String, model: String, transcript: String, languageCode: String) async throws -> String {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return transcript }
        
        let languageName = LanguageHelper.languageName(for: languageCode)
        
        let systemPrompt = """
        You are an expert \(languageName) language assistant specializing in correcting speech-to-text transcriptions, especially for language learners with non-native accents.
        
        Your task is to:
        1. Correct common transcription errors caused by pronunciation issues
        2. Fix grammar and word order errors
        3. Correct common mispronunciations
        4. Fix missing diacritical marks and special characters specific to \(languageName)
        5. Correct word boundaries and spacing issues
        6. Preserve the speaker's intended meaning and natural speech patterns
        7. Keep the tone and style of the original (formal/informal)
        
        Return ONLY the corrected \(languageName) text, nothing else. Do not translate, explain, or add commentary.
        """
        
        let userPrompt = """
        Correct this \(languageName) transcription, fixing pronunciation-based errors and improving accuracy:
        
        \(transcript)
        """
        
        let messages = [
            OAChatMessage(role: "system", content: systemPrompt),
            OAChatMessage(role: "user", content: userPrompt)
        ]
        
        // Use slightly higher temperature (0.3) for correction to allow more creative fixes
        let result = try await client.chatCompletion(baseURL: provider.baseURL, apiKey: apiKey, model: model, messages: messages, temperature: 0.3)
        return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? transcript : result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Legacy method: Automatically correct Spanish transcription errors (for backward compatibility)
    @available(*, deprecated, message: "Use correctTranscription(provider:apiKey:model:transcript:languageCode:) instead")
    func correctSpanishTranscription(provider: Provider, apiKey: String, model: String, transcript: String) async throws -> String {
        return try await correctTranscription(provider: provider, apiKey: apiKey, model: model, transcript: transcript, languageCode: "es")
    }
}


