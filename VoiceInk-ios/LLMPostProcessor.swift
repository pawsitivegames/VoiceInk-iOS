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
    
    /// Automatically correct Spanish transcription errors, especially for non-native speakers with accents
    /// This helps improve accuracy when pronunciation isn't perfect
    func correctSpanishTranscription(provider: Provider, apiKey: String, model: String, transcript: String) async throws -> String {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return transcript }
        
        let systemPrompt = """
        You are an expert Spanish language assistant specializing in correcting speech-to-text transcriptions, especially for language learners with non-native accents.
        
        Your task is to:
        1. Correct common transcription errors caused by pronunciation issues (e.g., "que" vs "ke", "es" vs "eh", "por" vs "po")
        2. Fix grammar and word order errors
        3. Correct common mispronunciations (e.g., "hablar" might be transcribed as "ablar" or "hablar" as "ablar")
        4. Fix missing accents (á, é, í, ó, ú, ñ)
        5. Correct word boundaries (e.g., "del" vs "de el", "al" vs "a el")
        6. Preserve the speaker's intended meaning and natural speech patterns
        7. Keep the tone and style of the original (formal/informal)
        
        Return ONLY the corrected Spanish text, nothing else. Do not translate, explain, or add commentary.
        """
        
        let userPrompt = """
        Correct this Spanish transcription, fixing pronunciation-based errors and improving accuracy:
        
        \(transcript)
        """
        
        let messages = [
            OAChatMessage(role: "system", content: systemPrompt),
            OAChatMessage(role: "user", content: userPrompt)
        ]
        
        // Use slightly higher temperature (0.3) for Spanish correction to allow more creative fixes
        let result = try await client.chatCompletion(baseURL: provider.baseURL, apiKey: apiKey, model: model, messages: messages, temperature: 0.3)
        return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? transcript : result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


