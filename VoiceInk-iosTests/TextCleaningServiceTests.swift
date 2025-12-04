//
//  TextCleaningServiceTests.swift
//  VoiceInk-iosTests
//
//  Unit tests for TextCleaningService
//

import Testing
@testable import VoiceInk_ios

struct TextCleaningServiceTests {
    
    @Test("Cleans multiple newlines to double newline")
    func testMultipleNewlines() async throws {
        let input = "Line 1\n\n\n\nLine 2"
        let result = TextCleaningService.cleanTranscriptionText(input)
        #expect(result == "Line 1\n\nLine 2")
    }
    
    @Test("Cleans multiple spaces to single space")
    func testMultipleSpaces() async throws {
        let input = "Hello    world"
        let result = TextCleaningService.cleanTranscriptionText(input)
        #expect(result == "Hello world")
    }
    
    @Test("Cleans tabs to single space")
    func testTabs() async throws {
        let input = "Hello\t\tworld"
        let result = TextCleaningService.cleanTranscriptionText(input)
        #expect(result == "Hello world")
    }
    
    @Test("Cleans mixed whitespace")
    func testMixedWhitespace() async throws {
        let input = "Hello   \t\t  world"
        let result = TextCleaningService.cleanTranscriptionText(input)
        #expect(result == "Hello world")
    }
    
    @Test("Trims leading and trailing whitespace")
    func testTrimming() async throws {
        let input = "   Hello world   "
        let result = TextCleaningService.cleanTranscriptionText(input)
        #expect(result == "Hello world")
    }
    
    @Test("Handles empty string")
    func testEmptyString() async throws {
        let input = ""
        let result = TextCleaningService.cleanTranscriptionText(input)
        #expect(result == "")
    }
    
    @Test("Handles whitespace-only string")
    func testWhitespaceOnly() async throws {
        let input = "   \n\t  "
        let result = TextCleaningService.cleanTranscriptionText(input)
        #expect(result == "")
    }
    
    @Test("Preserves single newlines")
    func testSingleNewline() async throws {
        let input = "Line 1\nLine 2"
        let result = TextCleaningService.cleanTranscriptionText(input)
        #expect(result == "Line 1\nLine 2")
    }
    
    @Test("Preserves single spaces")
    func testSingleSpace() async throws {
        let input = "Hello world"
        let result = TextCleaningService.cleanTranscriptionText(input)
        #expect(result == "Hello world")
    }
    
    @Test("Handles complex text with multiple issues")
    func testComplexText() async throws {
        let input = "   Hello    world\n\n\n\n   Test\t\t   "
        let result = TextCleaningService.cleanTranscriptionText(input)
        #expect(result == "Hello world\n\nTest")
    }
}

