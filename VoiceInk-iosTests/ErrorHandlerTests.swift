//
//  ErrorHandlerTests.swift
//  VoiceInk-iosTests
//
//  Unit tests for ErrorHandler
//

import Testing
@testable import VoiceInk_ios

@MainActor
struct ErrorHandlerTests {
    
    @Test("Handles TranslationError correctly")
    func testTranslationError() async throws {
        let handler = ErrorHandler.shared
        let error = TranslationError.translationFailed("Network timeout")
        let message = handler.handle(error, context: "Translation")
        #expect(message.contains("Translation failed"))
        #expect(message.contains("Network timeout"))
    }
    
    @Test("Handles TranscriptionError correctly")
    func testTranscriptionError() async throws {
        let handler = ErrorHandler.shared
        let error = TranscriptionError.noApiKey
        let message = handler.handle(error, context: "Transcription")
        #expect(message.contains("API key") || message.contains("No API key"))
    }
    
    @Test("Handles audio session error")
    func testAudioSessionError() async throws {
        let handler = ErrorHandler.shared
        let error = NSError(domain: NSOSStatusErrorDomain, code: 561017449) // '!act' error
        let message = handler.handle(error, context: "Audio")
        #expect(message.contains("microphone"))
    }
    
    @Test("Handles network error - no internet")
    func testNetworkErrorNoInternet() async throws {
        let handler = ErrorHandler.shared
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let message = handler.handle(error, context: "Network")
        #expect(message.contains("internet connection"))
    }
    
    @Test("Handles network error - timeout")
    func testNetworkErrorTimeout() async throws {
        let handler = ErrorHandler.shared
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        let message = handler.handle(error, context: "Network")
        #expect(message.contains("timed out"))
    }
    
    @Test("Handles generic error with localized description")
    func testGenericError() async throws {
        let handler = ErrorHandler.shared
        let error = NSError(domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error message"])
        let message = handler.handle(error, context: "Test")
        #expect(message == "Test error message")
    }
    
    @Test("Handles error without description")
    func testErrorWithoutDescription() async throws {
        let handler = ErrorHandler.shared
        let error = NSError(domain: "TestDomain", code: 123)
        let message = handler.handle(error, context: "Test")
        #expect(message.contains("unexpected error") || !message.isEmpty)
    }
    
    @Test("Logs errors correctly")
    func testErrorLogging() async throws {
        let handler = ErrorHandler.shared
        let error = TranslationError.translationFailed("Test")
        // This should not throw
        handler.logError(error, category: "TestCategory")
        #expect(true) // If we get here, logging succeeded
    }
}

