//
//  RiffWaveUtils.swift
//  VoiceInk-ios
//
//  Simple WAV file decoding utilities for Whisper
//  Adapted from whisper.swiftui demo
//

import Foundation

/// Decode WAV file to float samples for Whisper transcription
/// PERFORMANCE: Uses async file reading to avoid blocking the thread
func decodeWaveFile(_ url: URL) async throws -> [Float] {
    // Check file size first to avoid reading extremely large files
    let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let fileSize = fileAttributes[.size] as? Int64 ?? 0
    guard fileSize > 0 && fileSize < 100_000_000 else { // 100MB limit
        throw NSError(domain: "RiffWaveUtils", code: 1, userInfo: [NSLocalizedDescriptionKey: "WAV file is too large or invalid"])
    }
    
    // Read file data asynchronously
    let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fileData = try Data(contentsOf: url)
                continuation.resume(returning: fileData)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // Basic WAV header validation
    guard data.count > 44 else {
        throw NSError(domain: "RiffWaveUtils", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid WAV file - too small"])
    }
    
    // Extract samples starting from byte 44 (after WAV header)
    // PERFORMANCE: Pre-allocate array capacity for better memory efficiency
    let sampleCount = (data.count - 44) / 2
    var floats = [Float]()
    floats.reserveCapacity(sampleCount)
    
    for offset in stride(from: 44, to: data.count, by: 2) {
        let short = data[offset..<offset + 2].withUnsafeBytes {
            Int16(littleEndian: $0.load(as: Int16.self))
        }
        // Convert to normalized float (-1.0 to 1.0)
        floats.append(max(-1.0, min(Float(short) / 32767.0, 1.0)))
    }
    
    return floats
}
