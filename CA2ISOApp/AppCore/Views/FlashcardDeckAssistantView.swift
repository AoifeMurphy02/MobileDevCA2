//
//  FlashcardDeckAssistantView.swift
//  CA2ISOApp
//
//  Created by Meghana on 18/04/2026.
//

import SwiftUI

private struct FlashcardAssistantMessage: Identifiable, Equatable {
    let id: UUID
    let role: FlashcardDeckAssistantRole
    let text: String
    let supportingQuote: String
    let confidence: FlashcardConfidence?
    let followUp: String

    init(
        id: UUID = UUID(),
        role: FlashcardDeckAssistantRole,
        text: String,
        supportingQuote: String = "",
        confidence: FlashcardConfidence? = nil,
        followUp: String = ""
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.supportingQuote = supportingQuote
        self.confidence = confidence
        self.followUp = followUp
    }
}

struct FlashcardDeckAssistantView: View {
    @Environment(\.dismiss) private var dismiss

    let flashcardSet: FlashcardSet

    @State private var draftQuestion = ""
    @State private var messages: [FlashcardAssistantMessage] = []
    @State private var isLoading = false
    @State private var showSettings = false
    @State private var errorMessage = ""
    @State private var showErrorAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if FlashcardAISettingsStore.isCloudReady() {
                    chatView
                } else {
                    setupView
                }
            }
            .navigationTitle("Deck Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                FlashcardAISettingsView()
            }
            .alert("Assistant Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                seedGreetingIfNeeded()
            }
        }
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()

            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 42))
                .foregroundColor(Color(red: 0.25, green: 0.53, blue: 0.94))

            Text(setupTitle)
                .font(.title3.weight(.bold))

            Text(setupDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(FlashcardAISettingsStore.statusText())
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)

            Button {
                showSettings = true
            } label: {
                Text("Open AI Settings")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.25, green: 0.53, blue: 0.94))
                    .clipShape(Capsule())
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(AppTheme.surface)
    }

    private var chatView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(messages) { message in
                            FlashcardAssistantBubble(message: message)
                                .id(message.id)
                        }

                        if isLoading {
                            HStack {
                                ProgressView()
                                Text("Thinking through your deck...")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(18)
                }
                .background(AppTheme.background)
                .onChange(of: messages.count) { _, _ in
                    if let lastMessage = messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            VStack(spacing: 10) {
                Text("Ask about concepts, summaries, comparisons, or what a card really means.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Ask about this deck...", text: $draftQuestion, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)

                    Button {
                        Task {
                            await sendCurrentMessage()
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(canSend ? Color(red: 0.25, green: 0.53, blue: 0.94) : .gray)
                    }
                    .disabled(!canSend)
                }
            }
            .padding(18)
            .background(AppTheme.surface)
        }
    }

    private var canSend: Bool {
        !draftQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    private func seedGreetingIfNeeded() {
        guard messages.isEmpty else { return }

        messages = [
            FlashcardAssistantMessage(
                role: .assistant,
                text: "Ask me anything about \(flashcardSet.title). I’ll stay grounded in the deck source and keep the answer short and clear."
            )
        ]
    }

    @MainActor
    private func sendCurrentMessage() async {
        let question = draftQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        let userMessage = FlashcardAssistantMessage(role: .user, text: question)
        messages.append(userMessage)
        draftQuestion = ""
        isLoading = true

        let recentTurns = messages
            .suffix(8)
            .map { message in
                FlashcardDeckAssistantTurn(role: message.role, message: message.text)
            }
        let deckContext = FlashcardDeckAssistantContext(
            title: flashcardSet.title,
            studyArea: flashcardSet.studyArea,
            topic: flashcardSet.topic,
            sourceType: flashcardSet.sourceType,
            rawText: flashcardSet.rawText,
            cards: flashcardSet.cards
                .sorted(by: { $0.orderIndex < $1.orderIndex })
                .map { card in
                    FlashcardDeckAssistantCardContext(
                        question: card.question,
                        answer: card.answer,
                        orderIndex: card.orderIndex
                    )
                }
        )

        do {
            guard let configuredProvider = FlashcardAISettingsStore.configuredProvider() else {
                throw NSError(domain: "FlashcardDeckAssistant", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "The selected AI mode is not ready yet."
                ])
            }

            let reply = try await configuredProvider.provider.answerQuestion(
                question,
                about: deckContext,
                recentTurns: recentTurns
            )

            messages.append(
                FlashcardAssistantMessage(
                    role: .assistant,
                    text: reply.answer,
                    supportingQuote: reply.supportingQuote,
                    confidence: reply.confidence,
                    followUp: reply.followUp
                )
            )
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }

        isLoading = false
    }

    private var setupTitle: String {
        switch FlashcardAISettingsStore.currentMode() {
        case .local:
            return "An AI assistant is not enabled yet."
        case .appleIntelligence:
            return "Apple Intelligence is not ready yet."
        case .openAI:
            return "OpenAI hybrid mode is not ready yet."
        }
    }

    private var setupDescription: String {
        switch FlashcardAISettingsStore.currentMode() {
        case .local:
            return "Select Apple Intelligence or OpenAI hybrid mode to ask grounded questions about this deck."
        case .appleIntelligence:
            return "Turn on Apple Intelligence on the device to ask precise questions about this deck, with answers grounded in the source text behind the cards."
        case .openAI:
            return "Turn on OpenAI hybrid mode and add your API key to ask precise questions about this deck, with answers grounded in the source text behind the cards."
        }
    }
}

private struct FlashcardAssistantBubble: View {
    let message: FlashcardAssistantMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundColor(message.role == .user ? .white : .black)

                if let confidence = message.confidence, message.role == .assistant {
                    Text(confidence.title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(confidenceTint(confidence))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(confidenceTint(confidence).opacity(0.14))
                        .clipShape(Capsule())
                }

                if !message.supportingQuote.isEmpty, message.role == .assistant {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Supporting Quote")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        Text(message.supportingQuote)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                if !message.followUp.isEmpty, message.role == .assistant {
                    Text("Try asking: \(message.followUp)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: 300, alignment: .leading)
            .background(bubbleColor)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var bubbleColor: Color {
        message.role == .user
            ? Color(red: 0.25, green: 0.53, blue: 0.94)
            : .white
    }

    private func confidenceTint(_ confidence: FlashcardConfidence) -> Color {
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
