//
//  GroqTranscriptionService.swift
//

import Foundation

struct GroqTranscriptionResponse: Decodable {
    let text: String?
}

protocol TranscriptionService {
    func transcribeAudioFile(apiBaseURL: URL, apiKey: String, model: String, fileURL: URL, language: String?) async throws -> String
    func verifyAPIKey(apiBaseURL: URL, _ apiKey: String) async -> Bool
}

struct GroqTranscriptionService: TranscriptionService {
    // OpenAI-compatible APIs. Caller supplies baseURL and model.

    /// Transcribe audio file using OpenAI-compatible API
    /// Only supports "en" (English) and "es" (Spanish) languages
    func transcribeAudioFile(apiBaseURL: URL, apiKey: String, model: String, fileURL: URL, language: String? = nil) async throws -> String {
        // Validate language parameter - only allow "en" or "es"
        var validatedLanguage: String? = nil
        if let lang = language {
            if lang == "en" || lang == "es" {
                validatedLanguage = lang
            } else {
                Logger.warning("Invalid language '\(lang)', only 'en' and 'es' are supported. Using auto-detection instead.", category: "GroqTranscriptionService")
                validatedLanguage = nil
            }
        }
        
        let components = URLComponents(url: apiBaseURL.appendingPathComponent("/v1/audio/transcriptions"), resolvingAgainstBaseURL: false)!
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // multipart/form-data
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()

        func appendFormField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        // model field
        appendFormField("model", model)
        // Only include language if it's "en" or "es"
        if let validatedLanguage {
            appendFormField("language", validatedLanguage)
        }

        // PERFORMANCE: Use async file reading to avoid blocking the thread
        // Check file size first to avoid reading extremely large files
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        guard fileSize > 0 && fileSize < 100_000_000 else { // 100MB limit
            throw NSError(domain: "GroqAPI", code: 400, userInfo: [NSLocalizedDescriptionKey: "Audio file is too large or invalid"])
        }
        
        // Read audio file data asynchronously
        let fileData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try Data(contentsOf: fileURL)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        let filename = fileURL.lastPathComponent
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "GroqAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        // Some OpenAI-compatible APIs return JSON with a text property; others return nested objects.
        // Try to parse a simple text response first, else fallback to raw string.
        if let decoded = try? JSONDecoder().decode(GroqTranscriptionResponse.self, from: data), let t = decoded.text {
            return t
        }
        if let str = String(data: data, encoding: .utf8) {
            return str
        }
        return ""
    }

    func verifyAPIKey(apiBaseURL: URL, _ apiKey: String) async -> Bool {
        // Hit a lightweight endpoint (models listing) to verify
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("/v1/models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }
}


