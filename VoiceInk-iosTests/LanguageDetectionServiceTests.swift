//
//  LanguageDetectionServiceTests.swift
//  VoiceInk-iosTests
//
//  Unit tests for LanguageDetectionService
//

import Testing
@testable import VoiceInk_ios

@MainActor
struct LanguageDetectionServiceTests {
    
    @Test("Detects English text correctly")
    func testEnglishDetection() async throws {
        let service = LanguageDetectionService.shared
        let result = service.detectLanguage(from: "Hello, how are you today?")
        #expect(result == "en")
    }
    
    @Test("Detects Spanish text correctly")
    func testSpanishDetection() async throws {
        let service = LanguageDetectionService.shared
        let result = service.detectLanguage(from: "Hola, ¿cómo estás hoy?")
        #expect(result == "es")
    }
    
    @Test("Detects Spanish with accents")
    func testSpanishWithAccents() async throws {
        let service = LanguageDetectionService.shared
        let result = service.detectLanguage(from: "El niño está aquí")
        #expect(result == "es")
    }
    
    @Test("Detects Spanish with ñ character")
    func testSpanishWithN() async throws {
        let service = LanguageDetectionService.shared
        let result = service.detectLanguage(from: "España es bonita")
        #expect(result == "es")
    }
    
    @Test("Returns nil for empty text")
    func testEmptyText() async throws {
        let service = LanguageDetectionService.shared
        let result = service.detectLanguage(from: "")
        #expect(result == nil)
    }
    
    @Test("Returns nil for whitespace-only text")
    func testWhitespaceOnly() async throws {
        let service = LanguageDetectionService.shared
        let result = service.detectLanguage(from: "   \n\t  ")
        #expect(result == nil)
    }
    
    @Test("Caches detection results")
    func testCaching() async throws {
        let service = LanguageDetectionService.shared
        let text = "This is a test sentence for caching"
        
        // First call
        let result1 = service.detectLanguage(from: text)
        
        // Second call should use cache
        let result2 = service.detectLanguage(from: text)
        
        #expect(result1 == result2)
        #expect(result1 == "en")
    }
    
    @Test("Handles mixed English and Spanish")
    func testMixedLanguage() async throws {
        let service = LanguageDetectionService.shared
        // More English words, should default to English
        let result = service.detectLanguage(from: "Hello, el niño está aquí")
        #expect(result == "en" || result == "es") // Either is acceptable for mixed
    }
    
    @Test("Handles Spanish with high score")
    func testSpanishHighScore() async throws {
        let service = LanguageDetectionService.shared
        let result = service.detectLanguage(from: "El la los las que de y a en es son está están con por para del al más muy también")
        #expect(result == "es")
    }
}

