//
//  LanguageDetectionService.swift
//  VoiceInk-ios
//
//  Language detection service extracted from RecordingManager
//  Follows Single Responsibility Principle
//

import Foundation

/// Service for detecting language from text using simple heuristics
/// Only supports English and Spanish - returns "es" for Spanish, "en" for English (or nil which defaults to English)
/// Results are cached for performance using NSCache (LRU behavior with automatic memory management)
@MainActor
class LanguageDetectionService {
    static let shared = LanguageDetectionService()
    
    // Optimized LRU cache for language detection using NSCache (automatic memory management)
    private let languageDetectionCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 200 // Limit number of entries
        cache.totalCostLimit = 1024 * 1024 // 1MB limit for memory safety
        return cache
    }()
    
    private init() {
        // Private initializer for singleton pattern
    }
    
    /// Detect language from text using simple heuristics
    /// Only supports English and Spanish - returns "es" for Spanish, "en" for English (or nil which defaults to English)
    /// Other languages are not supported and will default to English
    /// Results are cached for performance using NSCache (LRU behavior with automatic memory management)
    func detectLanguage(from text: String) -> String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        
        // Create a better hash key using the normalized text (lowercased, trimmed)
        // This reduces collisions compared to String.hashValue
        let normalizedText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = normalizedText as NSString
        
        // Check cache first
        if let cached = languageDetectionCache.object(forKey: cacheKey) {
            return cached as String
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
        
        Logger.debug("Language detection: Spanish score: \(spanishScore), English score: \(englishScore)", category: "LanguageDetectionService")
        
        // Determine result
        let result: String?
        if spanishScore > englishScore + 2 {
            result = "es"
        } else if englishScore >= spanishScore {
            result = "en"
        } else {
            result = "en" // Default to English
        }
        
        // Cache result using NSCache (automatically handles memory pressure and eviction)
        if let resultString = result {
            // Use text length as cost to help NSCache manage memory better
            let cost = normalizedText.count
            languageDetectionCache.setObject(resultString as NSString, forKey: cacheKey, cost: cost)
        }
        
        return result
    }
}

