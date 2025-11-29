import Foundation

/// Represents a language configuration for the app
struct LanguageConfiguration: Codable, Equatable {
    var sourceLanguageCode: String  // Language user speaks (e.g., "en", "es", "fr", "ar")
    var targetLanguageCode: String  // Language user wants to learn/translate to (e.g., "es", "en", "fr", "ar")
    
    init(sourceLanguageCode: String = "en", targetLanguageCode: String = "es") {
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCode = targetLanguageCode
    }
    
    /// Returns the opposite language code (for translation direction)
    func oppositeLanguageCode(for detectedCode: String?) -> String {
        guard let detected = detectedCode else {
            // If no detection, assume source language was spoken, translate to target
            return targetLanguageCode
        }
        
        // If detected language matches source, translate to target
        // If detected language matches target, translate to source
        if detected == sourceLanguageCode {
            return targetLanguageCode
        } else if detected == targetLanguageCode {
            return sourceLanguageCode
        } else {
            // Unknown language detected, default to translating to target
            return targetLanguageCode
        }
    }
}

/// Helper for language information (names, flags, codes)
struct LanguageHelper {
    /// Supported language codes and their display names
    static let supportedLanguages: [String: (name: String, flag: String, localeCode: String)] = [
        "en": ("English", "🇺🇸", "en-US"),
        "es": ("Spanish", "🇪🇸", "es-ES"),
        "fr": ("French", "🇫🇷", "fr-FR"),
        "de": ("German", "🇩🇪", "de-DE"),
        "it": ("Italian", "🇮🇹", "it-IT"),
        "pt": ("Portuguese", "🇵🇹", "pt-PT"),
        "ar": ("Arabic", "🇸🇦", "ar-SA"),
        "zh": ("Chinese", "🇨🇳", "zh-CN"),
        "ja": ("Japanese", "🇯🇵", "ja-JP"),
        "ko": ("Korean", "🇰🇷", "ko-KR"),
        "ru": ("Russian", "🇷🇺", "ru-RU"),
        "hi": ("Hindi", "🇮🇳", "hi-IN"),
        "nl": ("Dutch", "🇳🇱", "nl-NL"),
        "pl": ("Polish", "🇵🇱", "pl-PL"),
        "tr": ("Turkish", "🇹🇷", "tr-TR"),
        "sv": ("Swedish", "🇸🇪", "sv-SE"),
        "da": ("Danish", "🇩🇰", "da-DK"),
        "no": ("Norwegian", "🇳🇴", "no-NO"),
        "fi": ("Finnish", "🇫🇮", "fi-FI"),
        "cs": ("Czech", "🇨🇿", "cs-CZ"),
        "ro": ("Romanian", "🇷🇴", "ro-RO"),
        "hu": ("Hungarian", "🇭🇺", "hu-HU"),
        "el": ("Greek", "🇬🇷", "el-GR"),
        "he": ("Hebrew", "🇮🇱", "he-IL"),
        "th": ("Thai", "🇹🇭", "th-TH"),
        "vi": ("Vietnamese", "🇻🇳", "vi-VN"),
        "id": ("Indonesian", "🇮🇩", "id-ID"),
        "ms": ("Malay", "🇲🇾", "ms-MY"),
        "uk": ("Ukrainian", "🇺🇦", "uk-UA"),
        "bg": ("Bulgarian", "🇧🇬", "bg-BG"),
        "hr": ("Croatian", "🇭🇷", "hr-HR"),
        "sk": ("Slovak", "🇸🇰", "sk-SK"),
        "sl": ("Slovenian", "🇸🇮", "sl-SI"),
        "et": ("Estonian", "🇪🇪", "et-EE"),
        "lv": ("Latvian", "🇱🇻", "lv-LV"),
        "lt": ("Lithuanian", "🇱🇹", "lt-LT"),
        "mt": ("Maltese", "🇲🇹", "mt-MT"),
        "ga": ("Irish", "🇮🇪", "ga-IE"),
        "cy": ("Welsh", "🇬🇧", "cy-GB"),
        "is": ("Icelandic", "🇮🇸", "is-IS"),
        "mk": ("Macedonian", "🇲🇰", "mk-MK"),
        "sq": ("Albanian", "🇦🇱", "sq-AL"),
        "sr": ("Serbian", "🇷🇸", "sr-RS"),
        "bs": ("Bosnian", "🇧🇦", "bs-BA"),
        "me": ("Montenegrin", "🇲🇪", "me-ME")
    ]
    
    /// Get language name for a language code
    static func languageName(for code: String) -> String {
        return supportedLanguages[code]?.name ?? code.uppercased()
    }
    
    /// Get flag emoji for a language code
    static func flag(for code: String) -> String {
        return supportedLanguages[code]?.flag ?? "🌐"
    }
    
    /// Get locale code for a language code (for text-to-speech)
    static func localeCode(for code: String) -> String {
        return supportedLanguages[code]?.localeCode ?? "en-US"
    }
    
    /// Get all supported language codes
    static var allLanguageCodes: [String] {
        return Array(supportedLanguages.keys).sorted()
    }
    
    /// Get all supported languages as tuples (code, name, flag)
    static var allLanguages: [(code: String, name: String, flag: String)] {
        return supportedLanguages.map { (code: $0.key, name: $0.value.name, flag: $0.value.flag) }
            .sorted { $0.name < $1.name }
    }
    
    /// Check if a language code is supported
    static func isSupported(_ code: String) -> Bool {
        return supportedLanguages[code] != nil
    }
}

