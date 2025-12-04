import SwiftUI

struct LanguageSelectionView: View {
    let title: String
    @Binding var selectedLanguageCode: String
    let excludedLanguageCode: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            ForEach(LanguageHelper.allLanguages, id: \.code) { language in
                // Don't show excluded language (for target language picker)
                if language.code != excludedLanguageCode {
                    Button(action: {
                        selectedLanguageCode = language.code
                        dismiss()
                    }) {
                        HStack {
                            Text(language.flag)
                                .font(.title2)
                            Text(language.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if language.code == selectedLanguageCode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}


