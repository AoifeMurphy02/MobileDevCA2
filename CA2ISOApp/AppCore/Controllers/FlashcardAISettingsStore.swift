//
//  FlashcardAISettingsStore.swift
//  CA2ISOApp
//
//  Created by Meghana on 18/04/2026.
//

import Foundation
import Security

enum FlashcardAIMode: String, CaseIterable, Codable, Sendable {
    case local
    case appleIntelligence
    case openAI

    nonisolated var title: String {
        switch self {
        case .local:
            return "Local AI"
        case .appleIntelligence:
            return "Apple Intelligence"
        case .openAI:
            return "OpenAI Hybrid"
        }
    }

    nonisolated var description: String {
        switch self {
        case .local:
            return "Runs the on-device ranking and cleanup flow only."
        case .appleIntelligence:
            return "Uses Apple Intelligence on device to improve grounded flashcard generation."
        case .openAI:
            return "Uses grounded local analysis first, then improves the deck with OpenAI."
        }
    }
}

enum FlashcardAIModelOption: String, CaseIterable, Codable, Sendable {
    case chatLike = "gpt-5.3-chat-latest"
    case flagship = "gpt-5.4"
    case fast = "gpt-5.4-mini"

    nonisolated var title: String {
        switch self {
        case .chatLike:
            return "ChatGPT-like"
        case .flagship:
            return "Flagship"
        case .fast:
            return "Fast"
        }
    }

    nonisolated var description: String {
        switch self {
        case .chatLike:
            return "Closest to a polished chat-style study assistant."
        case .flagship:
            return "Best reasoning quality for harder academic material."
        case .fast:
            return "Faster and lighter for quick deck building."
        }
    }
}

struct FlashcardAISettings: Sendable {
    var mode: FlashcardAIMode
    var modelOption: FlashcardAIModelOption
    var apiKeyConfigured: Bool

    nonisolated init(
        mode: FlashcardAIMode,
        modelOption: FlashcardAIModelOption,
        apiKeyConfigured: Bool
    ) {
        self.mode = mode
        self.modelOption = modelOption
        self.apiKeyConfigured = apiKeyConfigured
    }
}

enum FlashcardAISettingsError: LocalizedError {
    case keychainSaveFailed(OSStatus)

    nonisolated var errorDescription: String? {
        switch self {
        case .keychainSaveFailed(let status):
            return "Could not save the OpenAI API key. Keychain status: \(status)."
        }
    }
}

enum FlashcardAISettingsStore {
    private nonisolated static let modeKey = "flashcard.ai.mode"
    private nonisolated static let modelKey = "flashcard.ai.model"
    private nonisolated static let keychainService = "CA2ISOApp.OpenAI"
    private nonisolated static let keychainAccount = "openai-api-key"

    nonisolated static func loadSettings() -> FlashcardAISettings {
        FlashcardAISettings(
            mode: currentMode(),
            modelOption: currentModelOption(),
            apiKeyConfigured: !loadAPIKey().isEmpty
        )
    }

    nonisolated static func currentMode() -> FlashcardAIMode {
        guard let storedValue = UserDefaults.standard.string(forKey: modeKey),
              let mode = FlashcardAIMode(rawValue: storedValue) else {
            return .local
        }

        return mode
    }

    nonisolated static func currentModelOption() -> FlashcardAIModelOption {
        guard let storedValue = UserDefaults.standard.string(forKey: modelKey),
              let modelOption = FlashcardAIModelOption(rawValue: storedValue) else {
            return .chatLike
        }

        return modelOption
    }

    nonisolated static func loadAPIKey() -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return ""
        }

        return apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func save(
        mode: FlashcardAIMode,
        modelOption: FlashcardAIModelOption,
        apiKey: String
    ) throws {
        UserDefaults.standard.set(mode.rawValue, forKey: modeKey)
        UserDefaults.standard.set(modelOption.rawValue, forKey: modelKey)
        try saveAPIKey(apiKey)
    }

    nonisolated static func saveAPIKey(_ apiKey: String) throws {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard !trimmedAPIKey.isEmpty else { return }

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecValueData: Data(trimmedAPIKey.utf8)
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw FlashcardAISettingsError.keychainSaveFailed(status)
        }
    }

    nonisolated static func configuredProvider() -> (any FlashcardLLMProvider)? {
        switch currentMode() {
        case .local:
            return nil
        case .appleIntelligence:
            return AppleIntelligenceFlashcardService.configuredProvider()
        case .openAI:
            return OpenAIFlashcardService.configuredProvider()
        }
    }

    nonisolated static func title(forGenerationMode generationMode: String) -> String {
        switch generationMode {
        case "apple-intelligence":
            return "Apple Intelligence"
        case "openai":
            return "OpenAI Hybrid"
        default:
            return "Local AI"
        }
    }

    nonisolated static func isCloudReady() -> Bool {
        switch currentMode() {
        case .local:
            return false
        case .appleIntelligence:
            return AppleIntelligenceFlashcardService.isReady()
        case .openAI:
            return !loadAPIKey().isEmpty
        }
    }

    nonisolated static func statusText() -> String {
        let mode = currentMode()
        let hasAPIKey = !loadAPIKey().isEmpty

        switch (mode, hasAPIKey) {
        case (.local, _):
            return "Using local AI only."
        case (.appleIntelligence, _):
            return AppleIntelligenceFlashcardService.statusText()
        case (.openAI, true):
            return "OpenAI hybrid mode is ready."
        case (.openAI, false):
            return "OpenAI hybrid mode is selected, but the API key is missing."
        }
    }
}
