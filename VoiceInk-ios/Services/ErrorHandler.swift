//
//  ErrorHandler.swift
//  VoiceInk-ios
//
//  Centralized error handling service
//  Follows Single Responsibility Principle - handles error mapping and presentation
//

import Foundation

/// Protocol for error handling to allow dependency injection and testing
protocol ErrorHandlerProtocol {
    /// Handle an error and return a user-friendly message
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - context: Context where the error occurred (e.g., "Transcription", "Translation")
    /// - Returns: User-friendly error message
    func handle(_ error: Error, context: String) -> String
    
    /// Log an error with appropriate level
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - category: Category for logging (e.g., "TranscriptionService")
    func logError(_ error: Error, category: String)
}

/// Centralized error handler for consistent error presentation and logging
@MainActor
class ErrorHandler: ErrorHandlerProtocol {
    static let shared = ErrorHandler()
    
    private init() {
        // Private initializer for singleton pattern
    }
    
    /// Handle an error and return a user-friendly message
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - context: Context where the error occurred (e.g., "Transcription", "Translation")
    /// - Returns: User-friendly error message
    func handle(_ error: Error, context: String) -> String {
        // Log the error first
        logError(error, category: context)
        
        // Map error to user-friendly message
        if let translationError = error as? TranslationError {
            return handleTranslationError(translationError)
        }
        
        if let transcriptionError = error as? TranscriptionError {
            return handleTranscriptionError(transcriptionError)
        }
        
        // Handle NSError with specific domain/code mappings
        if let nsError = error as NSError? {
            // Handle audio session errors
            if nsError.domain == NSOSStatusErrorDomain {
                switch nsError.code {
                case 561017449: // '!act' error - microphone in use
                    return "Another app is using the microphone. Please try again."
                case 1718449215: // 'fmt?' error - format not supported
                    return "Audio format not supported. Please try again."
                default:
                    return "Audio error occurred: \(nsError.localizedDescription)"
                }
            }
            
            // Handle URL errors
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorNotConnectedToInternet:
                    return "No internet connection. Please check your network and try again."
                case NSURLErrorTimedOut:
                    return "Request timed out. Please try again."
                case NSURLErrorBadServerResponse:
                    return "Server error. Please try again later."
                case NSURLErrorCannotFindHost:
                    return "Cannot connect to server. Please check your connection."
                default:
                    return "Network error: \(nsError.localizedDescription)"
                }
            }
        }
        
        // Generic error handling - use localized description if available
        if let localizedError = error as? LocalizedError {
            return localizedError.errorDescription ?? localizedError.localizedDescription
        }
        
        // Fallback to error description
        return error.localizedDescription.isEmpty ? "An unexpected error occurred" : error.localizedDescription
    }
    
    /// Log an error with appropriate level
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - category: Category for logging (e.g., "TranscriptionService")
    func logError(_ error: Error, category: String) {
        // Determine log level based on error type
        if let nsError = error as NSError? {
            // Network errors are warnings (user can retry)
            if nsError.domain == NSURLErrorDomain {
                Logger.warning("\(category): \(error.localizedDescription)", category: category)
                return
            }
        }
        
        // Most errors are logged as errors
        Logger.error("\(category): \(error.localizedDescription)", category: category)
    }
    
    // MARK: - Private Error Handlers
    
    private func handleTranslationError(_ error: TranslationError) -> String {
        switch error {
        case .translatorUnavailable:
            return "Translation service is not available. Please ensure your device supports translation."
        case .unsupportedVersion:
            return "Translation requires iOS 18.0 or later. Please update your device."
        case .translationFailed(let message):
            return "Translation failed: \(message)"
        }
    }
    
    private func handleTranscriptionError(_ error: TranscriptionError) -> String {
        switch error {
        case .audioFileNotFound:
            return "Audio file not found"
        case .noApiKey:
            return "No API key configured for transcription"
        }
    }
}

