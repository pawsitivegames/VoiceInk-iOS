//
//  ViewUtilities.swift
//  VoiceInk-ios
//
//  Shared utility extensions to eliminate code duplication
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Custom Loading Indicator

/// Custom SwiftUI-only loading spinner to avoid UIKit rendering issues
/// This replaces ProgressView() which causes "Unable to render flattened version" warnings
struct LoadingSpinner: View {
    @State private var isAnimating = false
    var color: Color = .secondary
    var lineWidth: CGFloat = 2
    var size: CGFloat = 16
    
    var body: some View {
        Circle()
            .trim(from: 0.0, to: 0.7)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
            .frame(width: size, height: size)
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Shared Formatters

/// Shared RelativeDateTimeFormatter instance to avoid recreation on every render
private let sharedRelativeDateTimeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter
}()

// MARK: - Time Formatting

extension TimeInterval {
    /// Formats time interval as MM:SS string (with leading zero on minutes)
    var formattedTimeString: String {
        let s = Int(self)
        let m = s / 60
        let r = s % 60
        return String(format: "%02d:%02d", m, r)
    }
    
    /// Formats time interval as M:SS string (without leading zero on minutes, for audio players)
    var formattedTimeStringShort: String {
        let s = Int(self)
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }
}

// MARK: - Clipboard Utilities

/// Copies text to clipboard with haptic feedback
/// - Parameters:
///   - text: Text to copy
/// - Returns: The copied text
@discardableResult
func copyToClipboard(_ text: String) -> String {
    UIPasteboard.general.string = text
    
    // Haptic feedback
    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    impactFeedback.impactOccurred()
    
    return text
}

// MARK: - Date Formatting

extension Date {
    /// Formats date as relative time string using shared formatter
    var relativeTimeString: String {
        return sharedRelativeDateTimeFormatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Transcription Utilities

extension Transcription {
    /// Gets the text to display (enhanced text if available, otherwise original text)
    var displayText: String {
        if let enhancedText = enhancedText, !enhancedText.isEmpty {
            return enhancedText
        } else if !text.isEmpty {
            return text
        } else {
            return "No content available."
        }
    }
    
    /// Gets all text for sharing (original + translation)
    func allTextForSharing(translationLabel: String) -> String {
        var text = displayText
        if let translatedText = translatedText, !translatedText.isEmpty {
            text += "\n\n--- \(translationLabel) Translation ---\n\n" + translatedText
        }
        return text
    }
}

