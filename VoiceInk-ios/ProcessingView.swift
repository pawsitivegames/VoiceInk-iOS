import SwiftUI

struct ProcessingView: View {
    @Binding var isPresented: Bool
    let message: String
    
    var body: some View {
        // More prominent, readable banner - positioned for better visibility
        HStack(spacing: 16) {
            // Loading spinner - subtle animation
            ProgressView()
                .scaleEffect(1.0)
                .tint(.blue)
            
            // Message - larger font for better readability
            Text(message)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        }
        .padding(.horizontal, 16)
        .allowsHitTesting(false) // Allow touches to pass through to content below
    }
}

#Preview {
    ProcessingView(isPresented: .constant(true), message: "Processing transcription and translation...")
}

