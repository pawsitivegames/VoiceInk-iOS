//
//  ClipboardService.swift
//  VoiceInk-ios
//
//  Centralized clipboard service following DRY and Single Responsibility principles
//  Eliminates duplication of copyToClipboardWithMessage across views
//

import Foundation
import UIKit
import SwiftUI

/// Service for clipboard operations with toast notifications
/// Follows KISS and Single Responsibility principles
@MainActor
class ClipboardService: ObservableObject {
    static let shared = ClipboardService()
    
    @Published var showToast = false
    @Published var toastMessage = ""
    
    private var toastTask: Task<Void, Never>?
    
    private init() {
        // Private initializer for singleton pattern
    }
    
    /// Copy text to clipboard with haptic feedback and optional toast message
    /// - Parameters:
    ///   - text: Text to copy
    ///   - message: Optional toast message (default: "Copied to clipboard")
    /// - Returns: The copied text
    @discardableResult
    func copy(_ text: String, message: String = "Copied to clipboard") -> String {
        // Use existing copyToClipboard function from ViewUtilities (DRY principle)
        _ = copyToClipboard(text)
        
        // Show toast
        showToast(message: message)
        
        return text
    }
    
    /// Show toast message (automatically hides after 2 seconds)
    /// - Parameter message: Message to display
    func showToast(message: String) {
        // Cancel any existing toast task
        toastTask?.cancel()
        
        // Update message and show
        toastMessage = message
        withAnimation {
            showToast = true
        }
        
        // Hide toast after 2 seconds
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            withAnimation {
                showToast = false
            }
        }
    }
    
    /// Hide toast immediately
    func hideToast() {
        toastTask?.cancel()
        withAnimation {
            showToast = false
        }
    }
}

