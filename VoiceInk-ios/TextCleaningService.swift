//
//  TextCleaningService.swift
//  VoiceInk-ios
//
//  Text cleaning service extracted from RecordingManager
//  Follows Single Responsibility Principle
//

import Foundation

/// Service for cleaning transcription text using pre-compiled regex patterns
/// Made internal so it can be reused across the codebase
struct TextCleaningService {
    // PERFORMANCE: Pre-compiled regex patterns for text cleaning (compiled once, reused many times)
    private static let doubleNewlineRegex = try! NSRegularExpression(pattern: "\n\n+", options: [])
    private static let whitespaceRegex = try! NSRegularExpression(pattern: "[ \t]+", options: [])
    
    /// Clean transcription text using pre-compiled regex patterns for better performance
    /// This is faster than compiling regex on each call
    /// - Parameter text: Raw transcription text to clean
    /// - Returns: Cleaned text with normalized whitespace
    static func cleanTranscriptionText(_ text: String) -> String {
        // Trim whitespace first
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Replace multiple newlines with double newline using pre-compiled regex
        cleaned = doubleNewlineRegex.stringByReplacingMatches(
            in: cleaned,
            options: [],
            range: NSRange(location: 0, length: cleaned.utf16.count),
            withTemplate: "\n\n"
        )
        
        // Replace multiple spaces/tabs with single space using pre-compiled regex
        cleaned = whitespaceRegex.stringByReplacingMatches(
            in: cleaned,
            options: [],
            range: NSRange(location: 0, length: cleaned.utf16.count),
            withTemplate: " "
        )
        
        return cleaned
    }
}

