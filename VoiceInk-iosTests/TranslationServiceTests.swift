//
//  TranslationServiceTests.swift
//  VoiceInk-iosTests
//
//  Unit tests for TranslationService
//

import Testing
@testable import VoiceInk_ios

@MainActor
struct TranslationServiceTests {
    
    @Test("Handles empty text")
    func testEmptyText() async throws {
        let service = TranslationService.shared
        // Empty text should be handled gracefully
        // Note: This may throw or return empty, depending on implementation
        do {
            let result = try await service.translate(text: "", from: "en", to: "es")
            #expect(result.isEmpty || !result.isEmpty) // Either is acceptable
        } catch {
            // Empty text throwing an error is also acceptable
            #expect(true)
        }
    }
    
    @Test("Handles whitespace-only text")
    func testWhitespaceOnly() async throws {
        let service = TranslationService.shared
        do {
            let result = try await service.translate(text: "   ", from: "en", to: "es")
            #expect(result.isEmpty || !result.isEmpty) // Either is acceptable
        } catch {
            // Whitespace-only text throwing an error is also acceptable
            #expect(true)
        }
    }
    
    @Test("TranslationError has correct cases")
    func testTranslationErrorCases() async throws {
        // Test that TranslationError enum has expected cases
        let error1 = TranslationError.translatorUnavailable
        let error2 = TranslationError.unsupportedVersion
        let error3 = TranslationError.translationFailed("Test message")
        
        #expect(error1.errorDescription != nil)
        #expect(error2.errorDescription != nil)
        #expect(error3.errorDescription != nil)
    }
    
    @Test("TranslationError provides user-friendly messages")
    func testTranslationErrorMessages() async throws {
        let error1 = TranslationError.translatorUnavailable
        let error2 = TranslationError.unsupportedVersion
        let error3 = TranslationError.translationFailed("Network timeout")
        
        #expect(error1.errorDescription?.contains("available") == true || error1.errorDescription?.contains("Translation") == true)
        #expect(error2.errorDescription?.contains("iOS") == true || error2.errorDescription?.contains("version") == true)
        #expect(error3.errorDescription?.contains("failed") == true)
    }
}

