//
//  AppleIntelligenceFlashcardService.swift
//  CA2ISOApp
//
//  Created by Meghana on 23/04/2026.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

private enum AppleIntelligenceFlashcardError: LocalizedError {
    case invalidResponse
    case missingOutput
    case decodingFailed

    nonisolated var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Apple Intelligence returned an invalid response."
        case .missingOutput:
            return "Apple Intelligence did not return any usable flashcard content."
        case .decodingFailed:
            return "Apple Intelligence returned data in an unexpected format."
        }
    }
}

private struct AppleIntelligenceDeckPayload: Sendable {
    let title: String
    let subject: String
    let topic: String
    let cards: [AppleIntelligenceCardPayload]

    nonisolated init(title: String, subject: String, topic: String, cards: [AppleIntelligenceCardPayload]) {
        self.title = title
        self.subject = subject
        self.topic = topic
        self.cards = cards
    }
}

private struct AppleIntelligenceCardPayload: Sendable {
    let question: String
    let answer: String
    let style: String
    let confidence: String
    let evidenceExcerpt: String

    nonisolated init(
        question: String,
        answer: String,
        style: String,
        confidence: String,
        evidenceExcerpt: String
    ) {
        self.question = question
        self.answer = answer
        self.style = style
        self.confidence = confidence
        self.evidenceExcerpt = evidenceExcerpt
    }
}

private struct AppleIntelligenceAssistantPayload: Sendable {
    let answer: String
    let supportingQuote: String
    let confidence: String
    let followUp: String

    nonisolated init(answer: String, supportingQuote: String, confidence: String, followUp: String) {
        self.answer = answer
        self.supportingQuote = supportingQuote
        self.confidence = confidence
        self.followUp = followUp
    }
}

@available(iOS 26.0, *)
private struct AppleIntelligenceFlashcardProvider: FlashcardLLMProvider {
    nonisolated init() { }

    nonisolated var providerKind: String { "apple-intelligence" }
    nonisolated var providerModelID: String { "apple.foundation-model" }

    nonisolated func generateDeckSuggestion(from request: FlashcardCloudGenerationRequest) async throws -> FlashcardCloudDeckSuggestion {
        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: """
            You are a grounded study assistant for flashcard generation.
            Use only the supplied notes.
            Do not invent facts, examples, or evidence.
            Keep wording short, reusable, and easy to revise from.
            Prefer fewer cards over vague or generic cards.
            Each question must name a concrete concept, process, material, property, or comparison from the source.
            Prefer 1 to 3 complete sentences per answer, or up to 4 complete bullet points.
            Never stop mid-sentence or mid-bullet.
            Return only the requested JSON object.
            """
        )

        let response = try await session.respond(
            to: groundedDeckPrompt(for: request),
            options: GenerationOptions(
                sampling: .greedy,
                temperature: nil,
                maximumResponseTokens: 900
            )
        )

        guard let data = jsonObjectString(from: response.content).data(using: .utf8) else {
            throw AppleIntelligenceFlashcardError.decodingFailed
        }

        let payload = try parseDeckPayload(from: data)
        let cards = payload.cards.compactMap { payload -> FlashcardCloudCardSuggestion? in
            let question = cleanupInlineText(payload.question)
            let answer = cleanupInlineText(payload.answer)
            guard !question.isEmpty, !answer.isEmpty else { return nil }

            return FlashcardCloudCardSuggestion(
                question: question,
                answer: answer,
                style: FlashcardPromptStyle(rawValue: cleanupInlineText(payload.style).lowercased()) ?? .summary,
                confidence: FlashcardConfidence(rawValue: cleanupInlineText(payload.confidence).lowercased()) ?? .medium,
                evidenceExcerpt: cleanupInlineText(payload.evidenceExcerpt)
            )
        }

        guard !cards.isEmpty else {
            throw AppleIntelligenceFlashcardError.missingOutput
        }

        return FlashcardCloudDeckSuggestion(
            title: cleanupInlineText(payload.title),
            subject: cleanupInlineText(payload.subject),
            topic: cleanupInlineText(payload.topic),
            cards: Array(cards.prefix(max(min(request.requestedCardCount, 18), 1)))
        )
    }

    nonisolated func answerQuestion(
        _ question: String,
        about deck: FlashcardDeckAssistantContext,
        recentTurns: [FlashcardDeckAssistantTurn]
    ) async throws -> FlashcardDeckAssistantAnswer {
        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: """
            You are a grounded deck assistant.
            Answer only from the supplied deck source and relevant flashcards.
            If the source is weak, say that clearly instead of guessing.
            Write complete sentences only.
            Return only the requested JSON object.
            """
        )

        let response = try await session.respond(
            to: groundedAssistantPrompt(
                for: question,
                deck: deck,
                recentTurns: recentTurns
            ),
            options: GenerationOptions(
                sampling: .greedy,
                temperature: nil,
                maximumResponseTokens: 700
            )
        )

        guard let data = jsonObjectString(from: response.content).data(using: .utf8) else {
            throw AppleIntelligenceFlashcardError.decodingFailed
        }

        let payload = try parseAssistantPayload(from: data)
        let answer = cleanupInlineText(payload.answer)
        guard !answer.isEmpty else {
            throw AppleIntelligenceFlashcardError.missingOutput
        }

        let supportingQuote = resolvedSupportingQuote(
            cleanupInlineText(payload.supportingQuote),
            question: question,
            answer: answer,
            sourceText: deck.rawText
        )

        return FlashcardDeckAssistantAnswer(
            answer: answer,
            supportingQuote: supportingQuote,
            confidence: FlashcardConfidence(rawValue: cleanupInlineText(payload.confidence).lowercased()) ?? .medium,
            followUp: cleanupInlineText(payload.followUp)
        )
    }

    private nonisolated func groundedDeckPrompt(for request: FlashcardCloudGenerationRequest) -> String {
        let sourceAnalysis = FlashcardSourceAnalyzer.analyze(request.text)
        let dominantConcepts = sourceAnalysis.dominantConcepts.prefix(8).joined(separator: ", ")
        let keySections = sourceAnalysis.sections
            .prefix(8)
            .map { section in
                "[\(section.title)]\n\(boundedText(section.body, limit: 450))"
            }
            .joined(separator: "\n\n")

        return """
        Build a strong flashcard deck from the grounded source below.

        Rules:
        - Return 1 to \(max(request.requestedCardCount, 1)) cards.
        - It is better to return fewer cards than weak filler.
        - Use only the supplied study material.
        - Avoid duplicates and generic filler.
        - Every evidence_excerpt must be copied exactly from the source text.
        - Use only these styles: definition, explanation, why, how, compare, summary.
        - Each question must be grammatical, standalone English.
        - Each question must mention a specific named concept from the focus material.
        - Each answer must directly answer the question in 1 to 3 complete sentences, or up to 4 complete bullet points.
        - Ignore dedications, author names, copyright notices, image credits, figure captions, tables of contents, review questions, page headers, and exercise instructions.
        - Do not output fragments like "How does to visible light work?"
        - Do not output vague prompts like "Why are properties important?" or "Explain Differences between".
        - Do not output answers like "1. Define ... 2. Describe ..."
        - Never end an answer halfway through a sentence or list.
        - If this request is a focused section, stay inside that section and use the document overview only for terminology.
        - Return only valid JSON with this exact shape and no markdown fences:
          {
            "title": "string",
            "subject": "string",
            "topic": "string",
            "cards": [
              {
                "question": "string",
                "answer": "string",
                "style": "definition|explanation|why|how|compare|summary",
                "confidence": "high|medium|low",
                "evidence_excerpt": "string"
              }
            ]
          }

        Requested title: \(fallbackValue(request.title, placeholder: "Smart Flashcards"))
        Requested subject: \(fallbackValue(request.subject, placeholder: "Infer from the notes"))
        Requested topic: \(fallbackValue(request.topic, placeholder: "Infer from the notes"))
        Source type: \(fallbackValue(request.sourceType, placeholder: "Study material"))
        Focus section: \(fallbackValue(request.focusTitle, placeholder: "Whole document"))

        Dominant concepts:
        \(dominantConcepts.isEmpty ? "None extracted." : dominantConcepts)

        Key sections:
        \(keySections.isEmpty ? "No section structure detected." : keySections)

        Document overview:
        \(request.documentContext.isEmpty ? "No extra overview supplied." : request.documentContext)

        Focus study material:
        \(boundedText(request.text, limit: request.focusTitle.isEmpty ? 6_000 : 1_600))
        """
    }

    private nonisolated func groundedAssistantPrompt(
        for question: String,
        deck: FlashcardDeckAssistantContext,
        recentTurns: [FlashcardDeckAssistantTurn]
    ) -> String {
        let relevantCards = relatedDeckCards(for: question, in: deck)
            .map { card in
                "- Q: \(card.question)\n  A: \(card.answer)"
            }
            .joined(separator: "\n")
        let conversationContext = recentTurns
            .suffix(6)
            .map { turn in
                "\(turn.role.rawValue.capitalized): \(turn.message)"
            }
            .joined(separator: "\n")

        return """
        Answer the student's question using only the grounded deck context below.

        Rules:
        - Be clear and direct.
        - Prefer short paragraphs.
        - If the source does not fully support the answer, say so clearly.
        - supporting_quote must be copied exactly from the source text.
        - Return only valid JSON with this exact shape and no markdown fences:
          {
            "answer": "string",
            "supporting_quote": "string",
            "confidence": "high|medium|low",
            "follow_up": "string"
          }

        Deck title: \(fallbackValue(deck.title, placeholder: "Untitled Deck"))
        Deck subject: \(fallbackValue(deck.subject, placeholder: "No subject"))
        Deck topic: \(fallbackValue(deck.topic, placeholder: "No topic"))
        Deck source type: \(fallbackValue(deck.sourceType, placeholder: "No source type"))

        Recent conversation:
        \(conversationContext.isEmpty ? "No previous turns." : conversationContext)

        Most relevant flashcards:
        \(relevantCards.isEmpty ? "No especially relevant cards found." : relevantCards)

        Source text:
        \(boundedText(deck.rawText, limit: 8_500))

        Student question:
        \(cleanupInlineText(question))
        """
    }

    private nonisolated func relatedDeckCards(
        for question: String,
        in deck: FlashcardDeckAssistantContext
    ) -> [FlashcardDeckAssistantCardContext] {
        let questionTokens = Set(tokens(in: question))
        guard !questionTokens.isEmpty else {
            return Array(deck.cards.sorted(by: { $0.orderIndex < $1.orderIndex }).prefix(4))
        }

        return deck.cards
            .sorted { lhs, rhs in
                let lhsScore = relevanceScore(for: lhs, questionTokens: questionTokens)
                let rhsScore = relevanceScore(for: rhs, questionTokens: questionTokens)
                if lhsScore == rhsScore {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhsScore > rhsScore
            }
            .filter { relevanceScore(for: $0, questionTokens: questionTokens) > 0 }
            .prefix(4)
            .map { $0 }
    }

    private nonisolated func relevanceScore(
        for card: FlashcardDeckAssistantCardContext,
        questionTokens: Set<String>
    ) -> Int {
        let cardTokens = Set(tokens(in: "\(card.question) \(card.answer)"))
        return questionTokens.intersection(cardTokens).count
    }

    private nonisolated func resolvedSupportingQuote(
        _ quote: String,
        question: String,
        answer: String,
        sourceText: String
    ) -> String {
        if !quote.isEmpty, containsNormalizedSnippet(quote, in: sourceText) {
            return quote
        }

        return FlashcardAIEnhancer.bestEvidenceExcerpt(
            for: FlashcardDraft(question: question, answer: answer, evidenceExcerpt: quote),
            sourceText: sourceText
        )
    }

    private nonisolated func boundedText(_ text: String, limit: Int) -> String {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedText.count > limit else { return cleanedText }

        let excerptLength = max(limit / 3, 1)
        let middleStart = cleanedText.index(
            cleanedText.startIndex,
            offsetBy: max((cleanedText.count - excerptLength) / 2, 0)
        )
        let middleEnd = cleanedText.index(
            middleStart,
            offsetBy: min(excerptLength, cleanedText.distance(from: middleStart, to: cleanedText.endIndex))
        )
        let endStart = cleanedText.index(
            cleanedText.endIndex,
            offsetBy: -min(excerptLength, cleanedText.count)
        )

        return """
        [Beginning]
        \(cleanedText.prefix(excerptLength))

        [Middle]
        \(cleanedText[middleStart..<middleEnd])

        [End]
        \(cleanedText[endStart...])
        """
    }

    private nonisolated func fallbackValue(_ text: String, placeholder: String) -> String {
        let cleanedText = cleanupInlineText(text)
        return cleanedText.isEmpty ? placeholder : cleanedText
    }

    private nonisolated func cleanupInlineText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func containsNormalizedSnippet(_ snippet: String, in text: String) -> Bool {
        let normalizedSnippet = normalizedSearchText(snippet)
        let normalizedText = normalizedSearchText(text)

        guard !normalizedSnippet.isEmpty, !normalizedText.isEmpty else {
            return false
        }

        return normalizedText.contains(normalizedSnippet)
    }

    private nonisolated func normalizedSearchText(_ text: String) -> String {
        cleanupInlineText(text)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private nonisolated func tokens(in text: String) -> [String] {
        normalizedSearchText(text)
            .components(separatedBy: " ")
            .filter { $0.count > 2 }
    }

    private nonisolated func jsonObjectString(from text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let startIndex = trimmedText.firstIndex(of: "{"),
           let endIndex = trimmedText.lastIndex(of: "}") {
            return String(trimmedText[startIndex...endIndex])
        }

        return trimmedText
    }

    private nonisolated func parseDeckPayload(from data: Data) throws -> AppleIntelligenceDeckPayload {
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard let json = jsonObject as? [String: Any],
              let title = json["title"] as? String,
              let subject = json["subject"] as? String,
              let topic = json["topic"] as? String,
              let rawCards = json["cards"] as? [[String: Any]] else {
            throw AppleIntelligenceFlashcardError.decodingFailed
        }

        let cards = try rawCards.map { cardJSON -> AppleIntelligenceCardPayload in
            guard let question = cardJSON["question"] as? String,
                  let answer = cardJSON["answer"] as? String,
                  let style = cardJSON["style"] as? String,
                  let confidence = cardJSON["confidence"] as? String,
                  let evidenceExcerpt = cardJSON["evidence_excerpt"] as? String else {
                throw AppleIntelligenceFlashcardError.decodingFailed
            }

            return AppleIntelligenceCardPayload(
                question: question,
                answer: answer,
                style: style,
                confidence: confidence,
                evidenceExcerpt: evidenceExcerpt
            )
        }

        return AppleIntelligenceDeckPayload(
            title: title,
            subject: subject,
            topic: topic,
            cards: cards
        )
    }

    private nonisolated func parseAssistantPayload(from data: Data) throws -> AppleIntelligenceAssistantPayload {
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard let json = jsonObject as? [String: Any],
              let answer = json["answer"] as? String,
              let supportingQuote = json["supporting_quote"] as? String,
              let confidence = json["confidence"] as? String,
              let followUp = json["follow_up"] as? String else {
            throw AppleIntelligenceFlashcardError.decodingFailed
        }

        return AppleIntelligenceAssistantPayload(
            answer: answer,
            supportingQuote: supportingQuote,
            confidence: confidence,
            followUp: followUp
        )
    }
}
#endif

enum AppleIntelligenceFlashcardService {
    nonisolated static func configuredProvider() -> (any FlashcardLLMProvider)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isReady() {
            return AppleIntelligenceFlashcardProvider()
        }
        #endif
        return nil
    }

    nonisolated static func isReady() -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return readinessState().isReady
        }
        #endif
        return false
    }

    nonisolated static func statusText() -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return readinessState().message
        }
        #endif
        return "Apple Intelligence is not available in this build."
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private nonisolated static func readinessState() -> (isReady: Bool, message: String) {
        let model = SystemLanguageModel.default

        guard model.supportsLocale(Locale.current) else {
            return (false, "Apple Intelligence is not ready for the current device language.")
        }

        switch model.availability {
        case .available:
            return (true, "Apple Intelligence is ready on this device.")
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return (false, "This device does not support Apple Intelligence.")
            case .appleIntelligenceNotEnabled:
                return (false, "Apple Intelligence is turned off on this device.")
            case .modelNotReady:
                return (false, "Apple Intelligence is still preparing the on-device model.")
            @unknown default:
                return (false, "Apple Intelligence is not available right now.")
            }
        }
    }
    #endif
}
