//
//  DeepgramTranscriptionService.swift
//

import Foundation

struct DeepgramTranscriptionResponse: Decodable {
    let results: DeepgramResults
}

struct DeepgramResults: Decodable {
    let channels: [DeepgramChannel]
}

struct DeepgramChannel: Decodable {
    let alternatives: [DeepgramAlternative]
}

struct DeepgramAlternative: Decodable {
    let transcript: String
}

struct DeepgramTranscriptionService: TranscriptionService {
    
    /// Transcribe audio file using Deepgram API
    /// Only supports "en" (English) and "es" (Spanish) languages
    func transcribeAudioFile(apiBaseURL: URL, apiKey: String, model: String, fileURL: URL, language: String? = nil) async throws -> String {
        // Validate language parameter - only allow "en" or "es"
        var validatedLanguage: String? = nil
        if let lang = language {
            if lang == "en" || lang == "es" {
                validatedLanguage = lang
            } else {
                Logger.warning("Invalid language '\(lang)', only 'en' and 'es' are supported. Using auto-detection instead.", category: "DeepgramTranscriptionService")
                validatedLanguage = nil
            }
        }
        
        // Build query parameters
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "diarize", value: "false")
        ]
        
        // Only include language if it's "en" or "es"
        if let validatedLanguage {
            queryItems.append(URLQueryItem(name: "language", value: validatedLanguage))
        }
        
        var components = URLComponents(url: apiBaseURL.appendingPathComponent("/v1/listen"), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        
        guard let url = components.url else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        
        // PERFORMANCE: Use async file reading to avoid blocking the thread
        // Check file size first to avoid reading extremely large files
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        guard fileSize > 0 && fileSize < 100_000_000 else { // 100MB limit
            throw NSError(domain: "DeepgramAPI", code: 400, userInfo: [NSLocalizedDescriptionKey: "Audio file is too large or invalid"])
        }
        
        // Read audio file data asynchronously
        let audioData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try Data(contentsOf: fileURL)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        request.httpBody = audioData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        
        guard (200..<300).contains(http.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "DeepgramAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: errorText])
        }
        
        let decoded = try JSONDecoder().decode(DeepgramTranscriptionResponse.self, from: data)
        return decoded.results.channels.first?.alternatives.first?.transcript ?? ""
    }
    
    func verifyAPIKey(apiBaseURL: URL, _ apiKey: String) async -> Bool {
        // Use the projects endpoint to verify the API key
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("/v1/projects"))
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }
}