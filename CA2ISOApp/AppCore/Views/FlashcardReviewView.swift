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

    @State private var errorMessage = ""
    @State private var showErrorAlert = false
    @State private var shouldOpenSavedDeck = false
    @State private var savedFlashcardSet: FlashcardSet?

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
                Text("Subject")
                    .font(.subheadline.weight(.semibold))
                TextField("Subject", text: $viewModel.flashcardDraftSubject)
                    .textFieldStyle(.roundedBorder)

                if !self.viewModel.subjectOptions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(self.viewModel.subjectOptions, id: \.self) { subject in
                                Button {
                                    self.viewModel.flashcardDraftSubject = subject
                                } label: {
                                    Text(subject)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(self.viewModel.flashcardDraftSubject == subject ? .white : Color(red: 0.25, green: 0.53, blue: 0.94))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            self.viewModel.flashcardDraftSubject == subject
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
                ForEach(self.viewModel.flashcardDraftCards.indices, id: \.self) { index in
                    FlashcardEditorCard(
                        index: index,
                        card: $viewModel.flashcardDraftCards[index],
                        canMoveUp: index > 0,
                        canMoveDown: index < self.viewModel.flashcardDraftCards.count - 1,
                        moveUp: {
                            moveCard(from: index, to: index - 1)
                        },
                        moveDown: {
                            moveCard(from: index, to: index + 1)
                        },
                        deleteAction: {
                            self.viewModel.flashcardDraftCards.remove(at: index)
                        }
                    )
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

            Button {
                self.viewModel.addEmptyFlashcardDraft(style: .summary)
            } label: {
                Text("Add Another Card")
                    .font(.headline)
                    .foregroundColor(Color(red: 0.25, green: 0.53, blue: 0.94))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .overlay(
                        Capsule()
                            .stroke(Color(red: 0.25, green: 0.53, blue: 0.94).opacity(0.4), lineWidth: 1.4)
                    )
            }
        }
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
        let deckDraft = FlashcardDeckDraft(
            title: viewModel.flashcardDraftTitle,
            sourceType: viewModel.flashcardDraftSourceType,
            subject: viewModel.flashcardDraftSubject,
            topic: viewModel.flashcardDraftTopic,
            rawText: viewModel.flashcardDraftRawText,
            cards: viewModel.flashcardDraftCards
        )

        do {
            let flashcardSet = try FlashcardImportService.buildSet(from: deckDraft)
            modelContext.insert(flashcardSet)
            try modelContext.save()

            if !flashcardSet.subject.isEmpty {
                viewModel.selectSubject(flashcardSet.subject)
            }
            savedFlashcardSet = flashcardSet
            viewModel.clearFlashcardDraft()
            shouldOpenSavedDeck = true
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
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

                    Label(card.style.title, systemImage: card.style.iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(red: 0.25, green: 0.53, blue: 0.94))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.94, green: 0.97, blue: 1.0))
                        .clipShape(Capsule())
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
