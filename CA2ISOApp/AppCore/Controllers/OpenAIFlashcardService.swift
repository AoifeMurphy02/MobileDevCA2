//
//  OpenAIFlashcardService.swift
//  CA2ISOApp
//
//  Created by Meghana on 18/04/2026.
//

import Foundation

struct FlashcardCloudGenerationRequest: Sendable {
    let title: String
    let studyArea: String
    let topic: String
    let sourceType: String
    let text: String
    let focusTitle: String
    let requestedCardCount: Int
    let documentContext: String

    nonisolated init(
        title: String,
        studyArea: String,
        topic: String,
        sourceType: String,
        text: String,
        focusTitle: String = "",
        requestedCardCount: Int = 12,
        documentContext: String = ""
    ) {
        self.title = title
        self.studyArea = studyArea
        self.topic = topic
        self.sourceType = sourceType
        self.text = text
        self.focusTitle = focusTitle
        self.requestedCardCount = requestedCardCount
        self.documentContext = documentContext
    }
}

struct FlashcardCloudCardSuggestion: Sendable {
    let question: String
    let answer: String
    let style: FlashcardPromptStyle
    let confidence: FlashcardConfidence
    let evidenceExcerpt: String

    nonisolated init(
        question: String,
        answer: String,
        style: FlashcardPromptStyle,
        confidence: FlashcardConfidence,
        evidenceExcerpt: String
    ) {
        self.question = question
        self.answer = answer
        self.style = style
        self.confidence = confidence
        self.evidenceExcerpt = evidenceExcerpt
    }
}

struct FlashcardCloudDeckSuggestion: Sendable {
    let title: String
    let studyArea: String
    let topic: String
    let cards: [FlashcardCloudCardSuggestion]

    nonisolated init(title: String, studyArea: String, topic: String, cards: [FlashcardCloudCardSuggestion]) {
        self.title = title
        self.studyArea = studyArea
        self.topic = topic
        self.cards = cards
    }
}

enum FlashcardDeckAssistantRole: String, Sendable {
    case user
    case assistant
}

struct FlashcardDeckAssistantTurn: Sendable {
    let role: FlashcardDeckAssistantRole
    let message: String

    nonisolated init(role: FlashcardDeckAssistantRole, message: String) {
        self.role = role
        self.message = message
    }
}

struct FlashcardDeckAssistantCardContext: Sendable {
    let question: String
    let answer: String
    let orderIndex: Int

    nonisolated init(question: String, answer: String, orderIndex: Int) {
        self.question = question
        self.answer = answer
        self.orderIndex = orderIndex
    }
}

struct FlashcardDeckAssistantContext: Sendable {
    let title: String
    let studyArea: String
    let topic: String
    let sourceType: String
    let rawText: String
    let cards: [FlashcardDeckAssistantCardContext]

    nonisolated init(
        title: String,
        studyArea: String,
        topic: String,
        sourceType: String,
        rawText: String,
        cards: [FlashcardDeckAssistantCardContext]
    ) {
        self.title = title
        self.studyArea = studyArea
        self.topic = topic
        self.sourceType = sourceType
        self.rawText = rawText
        self.cards = cards
    }
}

struct FlashcardDeckAssistantAnswer: Sendable {
    let answer: String
    let supportingQuote: String
    let confidence: FlashcardConfidence
    let followUp: String

    nonisolated init(
        answer: String,
        supportingQuote: String,
        confidence: FlashcardConfidence,
        followUp: String
    ) {
        self.answer = answer
        self.supportingQuote = supportingQuote
        self.confidence = confidence
        self.followUp = followUp
    }
}

protocol FlashcardLLMProvider: Sendable {
    var providerKind: String { get }
    var providerModelID: String { get }
    func generateDeckSuggestion(from request: FlashcardCloudGenerationRequest) async throws -> FlashcardCloudDeckSuggestion
    func answerQuestion(
        _ question: String,
        about deck: FlashcardDeckAssistantContext,
        recentTurns: [FlashcardDeckAssistantTurn]
    ) async throws -> FlashcardDeckAssistantAnswer
}

enum OpenAIFlashcardService {
    nonisolated static func configuredProvider() -> (any FlashcardLLMProvider)? {
        let settings = FlashcardAISettingsStore.loadSettings()
        let apiKey = FlashcardAISettingsStore.loadAPIKey()

        guard settings.mode == .openAI, !apiKey.isEmpty else {
            return nil
        }

        return OpenAIFlashcardProvider(modelOption: settings.modelOption, apiKey: apiKey)
    }
}

private enum OpenAIFlashcardError: LocalizedError {
    case invalidRequestBody
    case invalidResponse
    case missingOutput
    case requestFailed(Int, String)
    case decodingFailed

    nonisolated var errorDescription: String? {
        switch self {
        case .invalidRequestBody:
            return "The OpenAI request body could not be created."
        case .invalidResponse:
            return "The AI service returned an invalid response."
        case .missingOutput:
            return "The AI service did not return structured content."
        case .requestFailed(let statusCode, let message):
            return "The AI service failed with status \(statusCode): \(message)"
        case .decodingFailed:
            return "The AI service returned data in an unexpected format."
        }
    }
}

private struct OpenAIFlashcardProvider: FlashcardLLMProvider {
    let modelOption: FlashcardAIModelOption
    let apiKey: String

    nonisolated init(modelOption: FlashcardAIModelOption, apiKey: String) {
        self.modelOption = modelOption
        self.apiKey = apiKey
    }

    nonisolated var providerKind: String {
        "openai"
    }

    nonisolated var providerModelID: String {
        modelOption.rawValue
    }

    nonisolated func generateDeckSuggestion(from request: FlashcardCloudGenerationRequest) async throws -> FlashcardCloudDeckSuggestion {
        let responseText = try await performStructuredRequest(
            schemaName: "flashcard_deck_suggestion",
            schema: deckSuggestionSchema(),
            systemPrompt: deckGenerationSystemPrompt,
            userPrompt: groundedDeckPrompt(for: request)
        )

        guard let data = responseText.data(using: .utf8) else {
            throw OpenAIFlashcardError.decodingFailed
        }

        let payload = try parseDeckPayload(from: data)
        let cards = payload.cards.compactMap { cardPayload -> FlashcardCloudCardSuggestion? in
            let question = cleanupInlineText(cardPayload.question)
            let answer = cleanupInlineText(cardPayload.answer)
            guard !question.isEmpty, !answer.isEmpty else { return nil }

            return FlashcardCloudCardSuggestion(
                question: question,
                answer: answer,
                style: FlashcardPromptStyle(rawValue: cardPayload.style) ?? .summary,
                confidence: FlashcardConfidence(rawValue: cardPayload.confidence) ?? .medium,
                evidenceExcerpt: cleanupInlineText(cardPayload.evidenceExcerpt)
            )
        }

        guard !cards.isEmpty else {
            throw OpenAIFlashcardError.missingOutput
        }

        return FlashcardCloudDeckSuggestion(
            title: cleanupInlineText(payload.title),
            studyArea: cleanupInlineText(payload.studyArea),
            topic: cleanupInlineText(payload.topic),
            cards: Array(cards.prefix(max(min(request.requestedCardCount, 18), 1)))
        )
    }

    nonisolated func answerQuestion(
        _ question: String,
        about deck: FlashcardDeckAssistantContext,
        recentTurns: [FlashcardDeckAssistantTurn]
    ) async throws -> FlashcardDeckAssistantAnswer {
        let responseText = try await performStructuredRequest(
            schemaName: "flashcard_deck_answer",
            schema: assistantAnswerSchema(),
            systemPrompt: deckAssistantSystemPrompt,
            userPrompt: groundedAssistantPrompt(
                for: cleanupInlineText(question),
                deck: deck,
                recentTurns: recentTurns
            )
        )

        guard let data = responseText.data(using: .utf8) else {
            throw OpenAIFlashcardError.decodingFailed
        }

        let payload = try parseAssistantPayload(from: data)
        let answer = cleanupInlineText(payload.answer)
        guard !answer.isEmpty else {
            throw OpenAIFlashcardError.missingOutput
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
            confidence: FlashcardConfidence(rawValue: payload.confidence) ?? .medium,
            followUp: cleanupInlineText(payload.followUp)
        )
    }

    private nonisolated var deckGenerationSystemPrompt: String {
        """
        You are a grounded study assistant that creates precise, reusable flashcards.
        Use only the provided source material.
        Never invent facts, examples, or quotes.
        Keep cards short, understandable, and useful for revision.
        Prefer fewer cards over vague or generic cards.
        Questions must be grammatical and standalone.
        Each question must name a concrete concept, process, material, property, or comparison from the source.
        Answers must directly answer the question in 1 to 3 complete sentences, or up to 4 complete bullet points.
        Never stop mid-sentence or mid-bullet.
        """
    }

    private nonisolated var deckAssistantSystemPrompt: String {
        """
        You are a grounded deck assistant that answers like a precise study tutor.
        Use only the supplied deck source and related flashcards.
        If the evidence is weak, say so clearly instead of guessing.
        """
    }

    private nonisolated func groundedDeckPrompt(for request: FlashcardCloudGenerationRequest) -> String {
        let sourceAnalysis = FlashcardSourceAnalyzer.analyze(request.text)
        let dominantConcepts = sourceAnalysis.dominantConcepts.prefix(8).joined(separator: ", ")
        let sectionContext = sourceAnalysis.sections
            .prefix(8)
            .map { section in
                "[\(section.title)]\n\(boundedText(section.body, limit: 500))"
            }
            .joined(separator: "\n\n")

        return """
        Build a stronger revision deck from the grounded source below.

        Required behaviour:
        - Return 1 to \(max(request.requestedCardCount, 1)) cards.
        - It is better to return fewer cards than weak filler.
        - Keep the wording student-friendly and reusable.
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

        Requested deck details:
        - Title: \(fallbackValue(request.title, placeholder: "Smart Flashcards"))
        - studyArea: \(fallbackValue(request.studyArea, placeholder: "Use the source"))
        - Topic: \(fallbackValue(request.topic, placeholder: "Infer from the source"))
        - Source type: \(fallbackValue(request.sourceType, placeholder: "Study material"))
        - Focus section: \(fallbackValue(request.focusTitle, placeholder: "Whole document"))

        Dominant concepts:
        \(dominantConcepts.isEmpty ? "None extracted." : dominantConcepts)

        Key sections:
        \(sectionContext.isEmpty ? "No section structure detected." : sectionContext)

        Document overview:
        \(request.documentContext.isEmpty ? "No extra overview supplied." : request.documentContext)

        Focus study material:
        \(boundedText(request.text, limit: request.focusTitle.isEmpty ? 7_500 : 2_400))
        """
    }

    private nonisolated func groundedAssistantPrompt(
        for question: String,
        deck: FlashcardDeckAssistantContext,
        recentTurns: [FlashcardDeckAssistantTurn]
    ) -> String {
        let relatedCards = relatedDeckCards(for: question, in: deck)
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
        - Keep the answer clear and direct.
        - Prefer short paragraphs over long explanations.
        - If the question is not supported by the source, say the source is limited.
        - supporting_quote must come from the source text, not from your own wording.

        Deck title: \(fallbackValue(deck.title, placeholder: "Untitled Deck"))
        Deck studyArea: \(fallbackValue(deck.studyArea, placeholder: "No studyArea"))
        Deck topic: \(fallbackValue(deck.topic, placeholder: "No topic"))
        Deck source type: \(fallbackValue(deck.sourceType, placeholder: "No source type"))

        Recent conversation:
        \(conversationContext.isEmpty ? "No previous turns." : conversationContext)

        Most relevant flashcards:
        \(relatedCards.isEmpty ? "No especially relevant cards found." : relatedCards)

        Source text:
        \(boundedText(deck.rawText, limit: 9_000))

        Student question:
        \(question)
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
                let lhsScore = cardRelevanceScore(lhs, questionTokens: questionTokens)
                let rhsScore = cardRelevanceScore(rhs, questionTokens: questionTokens)
                if lhsScore == rhsScore {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhsScore > rhsScore
            }
            .prefix(4)
            .filter { cardRelevanceScore($0, questionTokens: questionTokens) > 0 }
            .map { $0 }
    }

    private nonisolated func cardRelevanceScore(
        _ card: FlashcardDeckAssistantCardContext,
        questionTokens: Set<String>
    ) -> Int {
        let cardTokens = Set(tokens(in: "\(card.question) \(card.answer)"))
        return questionTokens.intersection(cardTokens).count
    }

    private nonisolated func performStructuredRequest(
        schemaName: String,
        schema: [String: Any],
        systemPrompt: String,
        userPrompt: String
    ) async throws -> String {
        let body: [String: Any] = {
            var payload: [String: Any] = [
                "model": providerModelID,
                "input": [
                    [
                        "role": "system",
                        "content": [
                            [
                                "type": "input_text",
                                "text": systemPrompt
                            ]
                        ]
                    ],
                    [
                        "role": "user",
                        "content": [
                            [
                                "type": "input_text",
                                "text": userPrompt
                            ]
                        ]
                    ]
                ],
                "text": [
                    "format": [
                        "type": "json_schema",
                        "name": schemaName,
                        "schema": schema,
                        "strict": true
                    ]
                ]
            ]

            if modelOption != .chatLike {
                payload["reasoning"] = ["effort": "medium"]
            }

            return payload
        }()

        guard JSONSerialization.isValidJSONObject(body) else {
            throw OpenAIFlashcardError.invalidRequestBody
        }

        let data = try await performRequest(body: body)
        return try extractOutputText(from: data)
    }

    private nonisolated func performRequest(body: [String: Any]) async throws -> Data {
        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw OpenAIFlashcardError.invalidResponse
        }

        let requestData = try JSONSerialization.data(withJSONObject: body)

        for attempt in 1...3 {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 45
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.httpBody = requestData

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OpenAIFlashcardError.invalidResponse
                }

                if (200...299).contains(httpResponse.statusCode) {
                    return data
                }

                let message = extractErrorMessage(from: data)
                if shouldRetry(statusCode: httpResponse.statusCode), attempt < 3 {
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 600_000_000)
                    continue
                }

                throw OpenAIFlashcardError.requestFailed(httpResponse.statusCode, message)
            } catch {
                if shouldRetry(error: error), attempt < 3 {
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 600_000_000)
                    continue
                }

                throw error
            }
        }

        throw OpenAIFlashcardError.invalidResponse
    }

    private nonisolated func extractOutputText(from data: Data) throws -> String {
        let envelope = try parseResponseEnvelope(from: data)

        let text = envelope.output?
            .flatMap { $0.content ?? [] }
            .compactMap { content in
                guard content.type == "output_text" else { return nil }
                return content.text
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !text.isEmpty else {
            throw OpenAIFlashcardError.missingOutput
        }

        return text
    }

    private nonisolated func extractErrorMessage(from data: Data) -> String {
        guard let envelope = try? parseResponseEnvelope(from: data),
              let message = envelope.error?.message,
              !message.isEmpty else {
            return "Unknown error"
        }

        return message
    }

    private nonisolated func shouldRetry(statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
    }

    private nonisolated func shouldRetry(error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }

        switch urlError.code {
        case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .cannotFindHost:
            return true
        default:
            return false
        }
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

    private nonisolated func deckSuggestionSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "title": ["type": "string"],
                "studyArea": ["type": "string"],
                "topic": ["type": "string"],
                "cards": [
                    "type": "array",
                    "minItems": 10,
                    "maxItems": 18,
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "question": ["type": "string"],
                            "answer": ["type": "string"],
                            "style": [
                                "type": "string",
                                "enum": ["definition", "explanation", "why", "how", "compare", "summary"]
                            ],
                            "confidence": [
                                "type": "string",
                                "enum": ["low", "medium", "high"]
                            ],
                            "evidence_excerpt": ["type": "string"]
                        ],
                        "required": ["question", "answer", "style", "confidence", "evidence_excerpt"]
                    ]
                ]
            ],
            "required": ["title", "studyArea", "topic", "cards"]
        ]
    }

    private nonisolated func assistantAnswerSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "answer": ["type": "string"],
                "supporting_quote": ["type": "string"],
                "confidence": [
                    "type": "string",
                    "enum": ["low", "medium", "high"]
                ],
                "follow_up": ["type": "string"]
            ],
            "required": ["answer", "supporting_quote", "confidence", "follow_up"]
        ]
    }

    private nonisolated func parseDeckPayload(from data: Data) throws -> CloudDeckPayload {
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard let json = jsonObject as? [String: Any],
              let title = json["title"] as? String,
              let studyArea = json["studyArea"] as? String,
              let topic = json["topic"] as? String,
              let rawCards = json["cards"] as? [[String: Any]] else {
            throw OpenAIFlashcardError.decodingFailed
        }

        let cards = try rawCards.map { cardJSON -> CloudDeckCardPayload in
            guard let question = cardJSON["question"] as? String,
                  let answer = cardJSON["answer"] as? String,
                  let style = cardJSON["style"] as? String,
                  let confidence = cardJSON["confidence"] as? String,
                  let evidenceExcerpt = cardJSON["evidence_excerpt"] as? String else {
                throw OpenAIFlashcardError.decodingFailed
            }

            return CloudDeckCardPayload(
                question: question,
                answer: answer,
                style: style,
                confidence: confidence,
                evidenceExcerpt: evidenceExcerpt
            )
        }

        return CloudDeckPayload(title: title, studyArea: studyArea, topic: topic, cards: cards)
    }

    private nonisolated func parseAssistantPayload(from data: Data) throws -> AssistantPayload {
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard let json = jsonObject as? [String: Any],
              let answer = json["answer"] as? String,
              let supportingQuote = json["supporting_quote"] as? String,
              let confidence = json["confidence"] as? String,
              let followUp = json["follow_up"] as? String else {
            throw OpenAIFlashcardError.decodingFailed
        }

        return AssistantPayload(
            answer: answer,
            supportingQuote: supportingQuote,
            confidence: confidence,
            followUp: followUp
        )
    }

    private nonisolated func parseResponseEnvelope(from data: Data) throws -> OpenAIResponseEnvelope {
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard let json = jsonObject as? [String: Any] else {
            throw OpenAIFlashcardError.decodingFailed
        }

        let outputItems: [OpenAIOutputItem]? = (json["output"] as? [[String: Any]])?.map { itemJSON in
            let contentItems: [OpenAIContentItem]? = (itemJSON["content"] as? [[String: Any]])?.map { contentJSON in
                OpenAIContentItem(
                    type: contentJSON["type"] as? String,
                    text: contentJSON["text"] as? String
                )
            }

            return OpenAIOutputItem(content: contentItems)
        }

        let errorPayload: OpenAIErrorPayload?
        if let errorJSON = json["error"] as? [String: Any] {
            errorPayload = OpenAIErrorPayload(message: errorJSON["message"] as? String)
        } else {
            errorPayload = nil
        }

        return OpenAIResponseEnvelope(output: outputItems, error: errorPayload)
    }
}

private struct CloudDeckPayload: Sendable {
    let title: String
    let studyArea: String
    let topic: String
    let cards: [CloudDeckCardPayload]

    nonisolated init(title: String, studyArea: String, topic: String, cards: [CloudDeckCardPayload]) {
        self.title = title
        self.studyArea = studyArea
        self.topic = topic
        self.cards = cards
    }
}

private struct CloudDeckCardPayload: Sendable {
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

private struct AssistantPayload: Sendable {
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

private struct OpenAIResponseEnvelope: Sendable {
    let output: [OpenAIOutputItem]?
    let error: OpenAIErrorPayload?

    nonisolated init(output: [OpenAIOutputItem]?, error: OpenAIErrorPayload?) {
        self.output = output
        self.error = error
    }
}

private struct OpenAIOutputItem: Sendable {
    let content: [OpenAIContentItem]?

    nonisolated init(content: [OpenAIContentItem]?) {
        self.content = content
    }
}

private struct OpenAIContentItem: Sendable {
    let type: String?
    let text: String?

    nonisolated init(type: String?, text: String?) {
        self.type = type
        self.text = text
    }
}

private struct OpenAIErrorPayload: Sendable {
    let message: String?

    nonisolated init(message: String?) {
        self.message = message
    }
}
