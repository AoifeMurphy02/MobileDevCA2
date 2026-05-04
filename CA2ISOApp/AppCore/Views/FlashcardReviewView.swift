//
//  FlashcardReviewView.swift
//  CA2ISOApp
//
//  Created by Meghana on 17/04/2026.
//

import SwiftData
import SwiftUI

struct FlashcardReviewView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var errorMessage = ""
    @State private var showErrorAlert = false
    @State private var shouldOpenSavedDeck = false
    @State private var savedFlashcardSet: FlashcardSet?
    @State private var draftWasFinalized = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                reviewSummary
                deckDetailsSection
                cardsSection
                actionSection
            }
            .padding(20)
            .padding(.bottom, 32)
        }
        .background(Color(red: 0.98, green: 0.99, blue: 1.0).ignoresSafeArea())
        .navigationTitle("Review Deck")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $shouldOpenSavedDeck) {
            if let savedFlashcardSet {
                FlashcardSetDetailView(flashcardSet: savedFlashcardSet)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Discard") {
                    draftWasFinalized = true
                    StudyNotificationManager.cancelDraftReviewReminder()
                    viewModel.clearFlashcardDraft()
                    dismiss()
                }
                .foregroundColor(.red)
            }
        }
        .alert("Could not save deck", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            draftWasFinalized = false
            viewModel.syncCurrentUserState(modelContext: modelContext)
            StudyNotificationManager.cancelDraftReviewReminder()
        }
        .onDisappear {
            scheduleDraftReviewReminderIfNeeded()
        }
        .onChange(of: scenePhase) { _, newValue in
            switch newValue {
            case .active:
                StudyNotificationManager.cancelDraftReviewReminder()
            case .background:
                scheduleDraftReviewReminderIfNeeded()
            default:
                break
            }
        }
    }

    private var reviewSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit the AI-ranked flashcards before saving. This keeps the deck cleaner and gives you the same review-first flow used by mainstream study apps.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                ReviewStatPill(
                    title: "\(viewModel.flashcardDraftCards.count) cards",
                    tint: Color(red: 0.25, green: 0.53, blue: 0.94)
                )

                ReviewStatPill(
                    title: viewModel.flashcardDraftSourceType.isEmpty ? "Smart Generation" : viewModel.flashcardDraftSourceType,
                    tint: Color(red: 0.0, green: 0.63, blue: 0.55)
                )

                if !viewModel.flashcardDraftAIGenerationMode.isEmpty {
                    ReviewStatPill(
                        title: FlashcardAISettingsStore.title(forGenerationMode: viewModel.flashcardDraftAIGenerationMode),
                        tint: Color(red: 0.87, green: 0.49, blue: 0.16)
                    )
                }
            }

            if !viewModel.flashcardDraftAIModelID.isEmpty {
                ReviewStatPill(
                    title: viewModel.flashcardDraftAIModelID,
                    tint: Color(red: 0.41, green: 0.37, blue: 0.86)
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 6)
    }

    private var deckDetailsSection: some View {
       @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 14) {
            Text("Deck Details")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.subheadline.weight(.semibold))
                TextField("Deck title", text: $viewModel.flashcardDraftTitle)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("studyArea")
                    .font(.subheadline.weight(.semibold))
                TextField("studyArea", text: $viewModel.flashcardDraftstudyArea)
                    .textFieldStyle(.roundedBorder)

                if !self.viewModel.studyAreaOptions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(self.viewModel.studyAreaOptions, id: \.self) { studyArea in
                                Button {
                                    self.viewModel.flashcardDraftstudyArea = studyArea
                                } label: {
                                    Text(studyArea)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(self.viewModel.flashcardDraftstudyArea == studyArea ? .white : Color(red: 0.25, green: 0.53, blue: 0.94))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            self.viewModel.flashcardDraftstudyArea == studyArea
                                            ? Color(red: 0.25, green: 0.53, blue: 0.94)
                                            : Color(red: 0.94, green: 0.97, blue: 1.0)
                                        )
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Topic")
                    .font(.subheadline.weight(.semibold))
                TextField("Topic", text: $viewModel.flashcardDraftTopic)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 6)
    }

    private var cardsSection: some View {
       @Bindable var viewModel = viewModel
        
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Cards")
                    .font(.headline)

                Spacer()

                Button {
                    self.viewModel.addEmptyFlashcardDraft(style: .summary)
                } label: {
                    Label("Add Card", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
            }

            if self.viewModel.flashcardDraftCards.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No cards in this deck yet.")
                        .font(.headline)
                    Text("Add a card to start building the deck.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                ForEach(Array(self.viewModel.flashcardDraftCards.enumerated()), id: \.element.id) { displayIndex, card in
                    // We check if the card still exists in the array before trying to draw it
                    if let cardBinding = bindingForCard(id: card.id) {
                        FlashcardEditorCard(
                            index: displayIndex,
                            card: cardBinding,
                            canMoveUp: displayIndex > 0,
                            canMoveDown: displayIndex < self.viewModel.flashcardDraftCards.count - 1,
                            moveUp: { moveCard(for: card.id, offset: -1) },
                            moveDown: { moveCard(for: card.id, offset: 1) },
                            deleteAction: { deleteCard(with: card.id) }
                        )
                    }
                }
            }
        }
    }

    private var actionSection: some View {
        VStack(spacing: 14) {
            Button {
                saveDeck()
            } label: {
                Text("Save and Study")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.25, green: 0.53, blue: 0.94))
                    .clipShape(Capsule())
            }

//            Button {
//                self.viewModel.addEmptyFlashcardDraft(style: .summary)
//            } label: {
//                Text("Add Another Card")
//                    .font(.headline)
//                    .foregroundColor(Color(red: 0.25, green: 0.53, blue: 0.94))
//                    .frame(maxWidth: .infinity)
//                    .padding(.vertical, 16)
//                    .overlay(
//                        Capsule()
//                            .stroke(Color(red: 0.25, green: 0.53, blue: 0.94).opacity(0.4), lineWidth: 1.4)
//                    )
//            }
        }
    }

    private func bindingForCard(id: UUID) -> Binding<FlashcardDraft>? {
        return Binding(
            get: {
                if let currentIndex = self.viewModel.flashcardDraftCards.firstIndex(where: { $0.id == id }) {
                    return self.viewModel.flashcardDraftCards[currentIndex]
                }
                // Fallback object to prevent "Index out of range"
                return FlashcardDraft(question: "", answer: "")
            },
            set: { updatedCard in
                // Refind the index when save
                if let currentIndex = self.viewModel.flashcardDraftCards.firstIndex(where: { $0.id == id }) {
                    self.viewModel.flashcardDraftCards[currentIndex] = updatedCard
                }
            }
        )
    }

    private func indexOfCard(with id: UUID) -> Int? {
        self.viewModel.flashcardDraftCards.firstIndex(where: { $0.id == id })
    }

    private func moveCard(for id: UUID, offset: Int) {
        guard let currentIndex = indexOfCard(with: id) else { return }
        let newIndex = currentIndex + offset
        moveCard(from: currentIndex, to: newIndex)
    }

    private func deleteCard(with id: UUID) {
       
        withAnimation {
            // remove the card that matches this specific ID
            self.viewModel.flashcardDraftCards.removeAll(where: { $0.id == id })
        }
        
        print("DEBUG: Card removed. Remaining count: \(viewModel.flashcardDraftCards.count)")
    }

    private func moveCard(from currentIndex: Int, to newIndex: Int) {
        guard self.viewModel.flashcardDraftCards.indices.contains(currentIndex),
              self.viewModel.flashcardDraftCards.indices.contains(newIndex) else {
            return
        }

        let card = self.viewModel.flashcardDraftCards.remove(at: currentIndex)
        self.viewModel.flashcardDraftCards.insert(card, at: newIndex)
    }

    private func saveDeck() {
        // 1. Validation: Ensure we actually have cards to save
        guard !viewModel.flashcardDraftCards.isEmpty else {
            self.errorMessage = "Please add at least one card to the deck."
            self.showErrorAlert = true
            return
        }

        let resolvedTitle = viewModel.flashcardDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "New Deck"
            : viewModel.flashcardDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedStudyArea = viewModel.flashcardDraftstudyArea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? viewModel.defaultstudyAreaForCreation
            : viewModel.flashcardDraftstudyArea.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSourceType = viewModel.flashcardDraftSourceType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Manual"
            : viewModel.flashcardDraftSourceType.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedOwnerEmail = viewModel.resolvedAuthenticatedEmail(modelContext: modelContext)

        guard !resolvedOwnerEmail.isEmpty else {
            self.errorMessage = "Please sign in again before saving this deck."
            self.showErrorAlert = true
            return
        }

        if viewModel.flashcardDraftstudyArea != resolvedStudyArea {
            viewModel.flashcardDraftstudyArea = resolvedStudyArea
        }

        let deckDraft = FlashcardDeckDraft(
            title: resolvedTitle,
            sourceType: resolvedSourceType,
            studyArea: resolvedStudyArea,
            topic: viewModel.flashcardDraftTopic,
            rawText: viewModel.flashcardDraftRawText,
            aiGenerationMode: viewModel.flashcardDraftAIGenerationMode,
            aiModelID: viewModel.flashcardDraftAIModelID,
            cards: viewModel.flashcardDraftCards
        )

        do {
            // 2. Build and Insert
            let flashcardSet = try FlashcardImportService.buildSet(
                from: deckDraft,
                ownerEmail: resolvedOwnerEmail
            )
            modelContext.insert(flashcardSet)
            
            // 3. Save to SQLite
            try modelContext.save()
            FlashcardStudyProgressStore.updateProgress(
                for: flashcardSet,
                reviewedCardCount: 0,
                learnedCardCount: 0,
                stillLearningCardCount: 0
            )
            print("SUCCESS: Saved deck with \(flashcardSet.cards.count) cards. owner=\(flashcardSet.ownerEmail), studyArea=\(flashcardSet.studyArea)")
            draftWasFinalized = true
            StudyNotificationManager.cancelDraftReviewReminder()

            // 4. Navigate
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.savedFlashcardSet = flashcardSet
                self.shouldOpenSavedDeck = true
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    viewModel.clearFlashcardDraft()
                }
            }
        } catch {
            // 5. Catch the specific error you were seeing
            print("DATABASE ERROR: \(error)")
            self.errorMessage = "Could not process deck: \(error.localizedDescription)"
            self.showErrorAlert = true
        }
    }

    private func scheduleDraftReviewReminderIfNeeded() {
        guard !draftWasFinalized, !viewModel.flashcardDraftCards.isEmpty else {
            StudyNotificationManager.cancelDraftReviewReminder()
            return
        }

        let deckTitle = viewModel.flashcardDraftTitle.isEmpty ? "Untitled Deck" : viewModel.flashcardDraftTitle
        StudyNotificationManager.scheduleDraftReviewReminder(
            deckTitle: deckTitle,
            studyArea: viewModel.flashcardDraftstudyArea,
            cardCount: viewModel.flashcardDraftCards.count
        )
    }
}

private struct FlashcardEditorCard: View {
    let index: Int
    @Binding var card: FlashcardDraft
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Card \(index + 1)")
                        .font(.headline)

                    HStack(spacing: 8) {
                        Label(card.style.title, systemImage: card.style.iconName)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color(red: 0.25, green: 0.53, blue: 0.94))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.94, green: 0.97, blue: 1.0))
                            .clipShape(Capsule())

                        ConfidencePill(confidence: card.confidence)
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    Button(action: moveUp) {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(!canMoveUp)
                    .opacity(canMoveUp ? 1 : 0.35)

                    Button(action: moveDown) {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(!canMoveDown)
                    .opacity(canMoveDown ? 1 : 0.35)

                    Button(role: .destructive, action: deleteAction) {
                        Image(systemName: "trash")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Question")
                    .font(.subheadline.weight(.semibold))
                EditorTextBox(text: $card.question, minHeight: 110)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Answer")
                    .font(.subheadline.weight(.semibold))
                EditorTextBox(text: $card.answer, minHeight: 140)
            }

            if !card.evidenceExcerpt.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Source Evidence")
                        .font(.subheadline.weight(.semibold))

                    Text(card.evidenceExcerpt)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0.98, green: 0.99, blue: 1.0))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 6)
    }
}

private struct EditorTextBox: View {
    @Binding var text: String
    let minHeight: CGFloat

    var body: some View {
        TextEditor(text: $text)
            .frame(minHeight: minHeight)
            .padding(10)
            .background(Color(red: 0.98, green: 0.99, blue: 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.blue.opacity(0.16), lineWidth: 1.2)
            )
    }
}

private struct ReviewStatPill: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct ConfidencePill: View {
    let confidence: FlashcardConfidence

    var body: some View {
        Text(confidence.shortTitle)
            .font(.caption.weight(.semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14))
            .clipShape(Capsule())
    }

    private var tint: Color {
        switch confidence {
        case .high:
            return Color(red: 0.18, green: 0.63, blue: 0.35)
        case .medium:
            return Color(red: 0.91, green: 0.57, blue: 0.13)
        case .low:
            return Color(red: 0.86, green: 0.27, blue: 0.24)
        }
    }
}
