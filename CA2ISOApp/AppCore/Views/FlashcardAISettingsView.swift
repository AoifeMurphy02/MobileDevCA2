//
//  FlashcardAISettingsView.swift
//  CA2ISOApp
//
//  Created by Meghana on 18/04/2026.
//

import SwiftUI

struct FlashcardAISettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMode = FlashcardAISettingsStore.currentMode()
    @State private var selectedModel = FlashcardAISettingsStore.currentModelOption()
    @State private var apiKey = FlashcardAISettingsStore.loadAPIKey()
    @State private var activeError: AppError?

    var body: some View {
        NavigationStack {
            Form {
                Section("AI Mode") {
                    Picker("Mode", selection: $selectedMode) {
                        ForEach(FlashcardAIMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Text(selectedMode.description)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                if selectedMode == .openAI {
                    Section("OpenAI Model") {
                        Picker("Model", selection: $selectedModel) {
                            ForEach(FlashcardAIModelOption.allCases, id: \.self) { model in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.title)
                                    Text(model.rawValue)
                                }
                                .tag(model)
                            }
                        }

                        Text(selectedModel.description)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                if selectedMode == .openAI {
                    Section("API Key") {
                        SecureField("OpenAI API key", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Text("The key is stored in the device Keychain and used only when OpenAI hybrid mode is enabled.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Status") {
                    Text(previewStatusText)
                        .font(.subheadline)
                        .foregroundColor(previewStatusColor)
                }

                Section("What Changes") {
                    Text(whatChangesText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("AI Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveSettings()
                    }
                    .fontWeight(.semibold)
                }
            }
            .appErrorAlert($activeError)
        }
    }

    private var previewStatusText: String {
        switch selectedMode {
        case .local:
            return "Using local AI only."
        case .appleIntelligence:
            return AppleIntelligenceFlashcardService.statusText()
        case .openAI:
            return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "OpenAI hybrid mode is selected, but the API key is missing."
                : "OpenAI hybrid mode is ready."
        }
    }

    private var previewStatusColor: Color {
        switch selectedMode {
        case .local:
            return .secondary
        case .appleIntelligence:
            return AppleIntelligenceFlashcardService.isReady() ? .green : .secondary
        case .openAI:
            return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .green
        }
    }

    private var whatChangesText: String {
        switch selectedMode {
        case .local:
            return "Local AI keeps the existing import, cleanup, ranking, and evidence pipeline fully on device."
        case .appleIntelligence:
            return "Local AI still cleans and ranks the source first, then Apple Intelligence improves the flashcards on device while the app validates the evidence against your notes."
        case .openAI:
            return "Local AI always extracts, filters, and ranks study content first. OpenAI hybrid mode then improves deck quality and powers the deck chat assistant while staying grounded in your source text."
        }
    }

    private func saveSettings() {
        do {
            try FlashcardAISettingsStore.save(
                mode: selectedMode,
                modelOption: selectedModel,
                apiKey: apiKey
            )
            dismiss()
        } catch {
            activeError = .storage("Could not save the AI settings. Please try again.")
        }
    }
}
