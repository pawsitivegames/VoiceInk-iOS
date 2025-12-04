//
//  ToastView.swift
//  VoiceInk-ios
//
//  Reusable toast component following DRY principle
//  Eliminates duplication of toast UI across views
//

import SwiftUI

/// Reusable toast view component
/// Follows KISS and DRY principles
struct ToastView: View {
    let message: String
    var style: ToastStyle = .default
    
    enum ToastStyle {
        case `default`
        case success
        case error
        
        var icon: String {
            switch self {
            case .default: return "checkmark.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.circle.fill"
            }
        }
        
        var iconColor: Color {
            switch self {
            case .default: return .white
            case .success: return .white
            case .error: return .white
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: style.icon)
                .foregroundStyle(style.iconColor)
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.black.opacity(0.85))
        }
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

/// View modifier for easy toast integration
struct ToastModifier: ViewModifier {
    @ObservedObject var clipboardService: ClipboardService
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if clipboardService.showToast {
                    ToastView(message: clipboardService.toastMessage)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: clipboardService.showToast)
                }
            }
    }
}

extension View {
    /// Add toast support using ClipboardService
    func toast(clipboardService: ClipboardService) -> some View {
        modifier(ToastModifier(clipboardService: clipboardService))
    }
}

