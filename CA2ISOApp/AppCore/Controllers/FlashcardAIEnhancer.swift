//
//  FlashcardAIEnhancer.swift
//  CA2ISOApp
//
//  Created by Meghana on 17/04/2026.
//

import Foundation
import NaturalLanguage

struct FlashcardDeckMetadataSuggestion: Sendable {
    let title: String
    let subject: String
    let topic: String

    nonisolated init(title: String, subject: String, topic: String) {
        self.title = title
        self.subject = subject
        self.topic = topic
    }
}

private struct RankedFlashcardDraft: Sendable {
    let draft: FlashcardDraft
    let score: Double
    let conceptKey: String

    nonisolated init(draft: FlashcardDraft, score: Double, conceptKey: String) {
        self.draft = draft
        self.score = score
        self.conceptKey = conceptKey
    }
}

enum FlashcardAIEnhancer {
    nonisolated static func finalizeDrafts(_ drafts: [FlashcardDraft], sourceText: String) -> [FlashcardDraft] {
        let cleanedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !drafts.isEmpty else { return [] }

        let rankedDrafts = drafts.map { draft in
            let refinedDraft = refine(draft, sourceText: cleanedText)
            return RankedFlashcardDraft(
                draft: refinedDraft,
                score: score(for: refinedDraft, sourceText: cleanedText),
                conceptKey: conceptKey(for: refinedDraft)
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.draft.question.count < rhs.draft.question.count
            }
            return lhs.score > rhs.score
        }

        var selectedDrafts: [FlashcardDraft] = []
        var usedConcepts = Set<String>()
        var styleCounts: [FlashcardPromptStyle: Int] = [:]

        for rankedDraft in rankedDrafts {
            let styleLimitReached = (styleCounts[rankedDraft.draft.style] ?? 0) >= 5
            let repeatedConcept = !rankedDraft.conceptKey.isEmpty && usedConcepts.contains(rankedDraft.conceptKey)

            if repeatedConcept && rankedDraft.score < 75 {
                continue
            }

            if styleLimitReached && rankedDraft.score < 82 {
                continue
            }

            selectedDrafts.append(rankedDraft.draft)

            if !rankedDraft.conceptKey.isEmpty {
                usedConcepts.insert(rankedDraft.conceptKey)
            }

            styleCounts[rankedDraft.draft.style, default: 0] += 1

            if selectedDrafts.count == 20 {
                break
            }
        }

        if selectedDrafts.count < min(10, rankedDrafts.count) {
            for rankedDraft in rankedDrafts where !selectedDrafts.contains(rankedDraft.draft) {
                selectedDrafts.append(rankedDraft.draft)
                if selectedDrafts.count == min(12, rankedDrafts.count) {
                    break
                }
            }
        }

        return selectedDrafts
    }

    nonisolated static func suggestMetadata(
        from sourceText: String,
        fallbackTitle: String,
        availableSubjects: [String],
        preferredSubject: String,
        fallbackTopic: String
    ) -> FlashcardDeckMetadataSuggestion {
        let cleanedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTopic = suggestTopic(from: cleanedText, fallbackTopic: fallbackTopic)
        let resolvedSubject = suggestSubject(
            from: cleanedText,
            availableSubjects: availableSubjects,
            preferredSubject: preferredSubject,
            fallbackTopic: resolvedTopic
        )
        let resolvedTitle = suggestTitle(
            fallbackTitle: fallbackTitle,
            topic: resolvedTopic,
            subject: resolvedSubject
        )

        return FlashcardDeckMetadataSuggestion(
            title: resolvedTitle,
            subject: resolvedSubject,
            topic: resolvedTopic
        )
    }

    private nonisolated static func refine(_ draft: FlashcardDraft, sourceText: String) -> FlashcardDraft {
        let normalizedQuestion = draft.question.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAnswer = draft.answer.trimmingCharacters(in: .whitespacesAndNewlines)

        if draft.style == .summary,
           normalizedQuestion.lowercased().hasPrefix("what is one key thing to remember about"),
           let concept = strongestConcept(in: normalizedAnswer.isEmpty ? sourceText : normalizedAnswer) {
            return FlashcardDraft(
                id: draft.id,
                question: "What are the key ideas in \(concept)?",
                answer: normalizedAnswer,
                style: .summary
            )
        }

        if draft.style == .explanation,
           normalizedQuestion.lowercased().hasPrefix("explain "),
           normalizedQuestion.count > 80,
           let concept = strongestConcept(in: normalizedQuestion) {
            return FlashcardDraft(
                id: draft.id,
                question: "Explain \(concept)",
                answer: normalizedAnswer,
                style: .explanation
            )
        }

        return FlashcardDraft(
            id: draft.id,
            question: normalizedQuestion,
            answer: normalizedAnswer,
            style: draft.style
        )
    }

    private nonisolated static func score(for draft: FlashcardDraft, sourceText: String) -> Double {
        var total = baseScore(for: draft.style)

        let questionLength = draft.question.count
        let answerLength = draft.answer.count
        let loweredQuestion = draft.question.lowercased()

        if questionLength >= 12 && questionLength <= 120 {
            total += 14
        } else {
            total -= 8
        }

        if answerLength >= 20 && answerLength <= 260 {
            total += 16
        } else if answerLength > 260 && answerLength <= 420 {
            total += 8
        } else {
            total -= 12
        }

        if !draft.question.lowercased().contains("what should you know about") {
            total += 6
        }

        if startsWithSupportedQuestionStem(draft.question) {
            total += 8
        } else {
            total -= 10
        }

        if draft.answer.contains("\n•") || draft.answer.contains("• ") {
            total += 8
        }

        if draft.answer.lowercased().contains("because") && draft.style == .why {
            total += 8
        }

        if conceptCoverageScore(for: draft, sourceText: sourceText) > 0 {
            total += 10
        }

        if conceptRichnessScore(for: draft.answer) >= 3 {
            total += 8
        }

        if loweredQuestion.contains("cover page")
            || loweredQuestion.contains("table of contents")
            || loweredQuestion.contains("one key thing to remember about") {
            total -= 30
        }

        if looksLikeLowValueText(draft.question) || looksLikeLowValueText(draft.answer) {
            total -= 35
        }

        let overlap = lexicalOverlap(question: draft.question, answer: draft.answer)
        total -= overlap * 10

        return total
    }

    private nonisolated static func baseScore(for style: FlashcardPromptStyle) -> Double {
        switch style {
        case .definition:
            return 78
        case .why:
            return 82
        case .how:
            return 80
        case .compare:
            return 83
        case .explanation:
            return 76
        case .summary:
            return 72
        }
    }

    private nonisolated static func conceptCoverageScore(for draft: FlashcardDraft, sourceText: String) -> Double {
        guard let concept = strongestConcept(in: draft.question + " " + draft.answer) else {
            return 0
        }

        let loweredText = sourceText.lowercased()
        return loweredText.contains(concept.lowercased()) ? 1 : 0
    }

    private nonisolated static func lexicalOverlap(question: String, answer: String) -> Double {
        let questionTokens = Set(tokens(in: question))
        let answerTokens = Set(tokens(in: answer))

        guard !questionTokens.isEmpty, !answerTokens.isEmpty else { return 0 }

        let intersection = questionTokens.intersection(answerTokens)
        return Double(intersection.count) / Double(max(questionTokens.count, 1))
    }

    private nonisolated static func conceptRichnessScore(for text: String) -> Int {
        Set(tokens(in: text)).count
    }

    private nonisolated static func conceptKey(for draft: FlashcardDraft) -> String {
        if let concept = strongestConcept(in: draft.question) {
            return concept.lowercased()
        }

        if let concept = strongestConcept(in: draft.answer) {
            return concept.lowercased()
        }

        return ""
    }

    private nonisolated static func suggestSubject(
        from text: String,
        availableSubjects: [String],
        preferredSubject: String,
        fallbackTopic: String
    ) -> String {
        let trimmedPreferredSubject = preferredSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSubjects = availableSubjects
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalizedSubjects.isEmpty else {
            return trimmedPreferredSubject
        }

        let loweredText = text.lowercased()
        let extractedKeywords = Set(tokens(in: text + " " + fallbackTopic))

        let subjectScores = normalizedSubjects.map { subject in
            (
                subject: subject,
                score: subjectScore(
                    for: subject,
                    loweredText: loweredText,
                    extractedKeywords: extractedKeywords
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.subject < rhs.subject
            }
            return lhs.score > rhs.score
        }

        if let bestMatch = subjectScores.first, bestMatch.score >= 16 {
            return bestMatch.subject
        }

        if !trimmedPreferredSubject.isEmpty {
            return trimmedPreferredSubject
        }

        return subjectScores.first?.subject ?? normalizedSubjects.first ?? ""
    }

    private nonisolated static func subjectScore(
        for subject: String,
        loweredText: String,
        extractedKeywords: Set<String>
    ) -> Int {
        let normalizedSubject = subject.lowercased()
        var score = 0

        if loweredText.contains(normalizedSubject) {
            score += 40
        }

        for token in tokens(in: subject) where extractedKeywords.contains(token) {
            score += 25
        }

        for keyword in subjectKeywords[normalizedSubject, default: []] {
            if loweredText.contains(keyword) {
                score += 8
            }
        }

        return score
    }

    private nonisolated static func suggestTitle(
        fallbackTitle: String,
        topic: String,
        subject: String
    ) -> String {
        let trimmedTitle = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedTitle.isEmpty && !isGenericTitle(trimmedTitle) {
            return trimmedTitle
        }

        if !trimmedTopic.isEmpty && !trimmedSubject.isEmpty {
            return "\(trimmedTopic) • \(trimmedSubject)"
        }

        if !trimmedTopic.isEmpty {
            return "\(trimmedTopic) Flashcards"
        }

        if !trimmedSubject.isEmpty {
            return "\(trimmedSubject) Flashcards"
        }

        return "Smart Flashcards"
    }

    private nonisolated static func suggestTopic(from text: String, fallbackTopic: String) -> String {
        let trimmedTopic = fallbackTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTopic.isEmpty {
            return trimmedTopic
        }

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let heading = lines.first(where: isLikelyHeading) {
            return heading
        }

        return strongestConcept(in: text) ?? ""
    }

    private nonisolated static func strongestConcept(in text: String) -> String? {
        let tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass])
        tagger.string = text

        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        var candidates: [String: Int] = [:]

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameTypeOrLexicalClass,
            options: options
        ) { tag, tokenRange in
            guard let tag else { return true }

            let token = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard token.count > 2 else { return true }

            switch tag {
            case .personalName, .placeName, .organizationName, .noun:
                if isUsefulKeyword(token) {
                    candidates[token, default: 0] += 1
                }
            default:
                break
            }

            return true
        }

        return candidates
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.count > rhs.key.count
                }
                return lhs.value > rhs.value
            }
            .first?
            .key
    }

    private nonisolated static func tokens(in text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && isUsefulKeyword($0) }
    }

    private nonisolated static func isGenericTitle(_ title: String) -> Bool {
        let genericTitles = [
            "photo flashcards",
            "pasted notes",
            "smart flashcards",
            "manual flashcards"
        ]

        return genericTitles.contains(title.lowercased())
    }

    private nonisolated static func startsWithSupportedQuestionStem(_ question: String) -> Bool {
        let loweredQuestion = question.lowercased()
        let stems = ["what ", "how ", "why ", "explain ", "compare "]
        return stems.contains(where: { loweredQuestion.hasPrefix($0) })
    }

    private nonisolated static func isLikelyHeading(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        return text.count <= 45 && words.count <= 6 && !text.contains("?") && !text.contains(":")
    }

    private nonisolated static func isUsefulKeyword(_ token: String) -> Bool {
        let stopWords: Set<String> = [
            "the", "and", "with", "from", "that", "this", "these", "those",
            "have", "has", "had", "into", "their", "there", "which", "what",
            "when", "where", "whose", "your", "about", "because", "through",
            "using", "used", "also", "than", "then", "them", "they", "will"
        ]

        return !stopWords.contains(token.lowercased())
    }

    private nonisolated static func looksLikeLowValueText(_ text: String) -> Bool {
        let loweredText = text.lowercased()
        let blockedTerms = [
            "table of contents", "contents", "student name", "student number",
            "module code", "copyright", "references", "bibliography",
            "acknowledgements", "submitted by", "prepared by"
        ]

        return blockedTerms.contains(where: { loweredText.contains($0) })
    }

    private nonisolated static let subjectKeywords: [String: [String]] = [
        "english": ["poem", "poetry", "novel", "theme", "character", "language", "essay", "author"],
        "french": ["french", "bonjour", "verb", "grammar", "vocabulary", "translation"],
        "german": ["german", "verb", "grammar", "vocabulary", "translation"],
        "spanish": ["spanish", "verb", "grammar", "vocabulary", "translation"],
        "mathematics": ["equation", "algebra", "geometry", "graph", "theorem", "calculus", "probability"],
        "maths": ["equation", "algebra", "geometry", "graph", "theorem", "calculus", "probability"],
        "physics": ["force", "velocity", "motion", "energy", "acceleration", "gravity", "mass"],
        "biology": ["cell", "organism", "photosynthesis", "ecosystem", "gene", "protein", "enzyme"],
        "chemistry": ["atom", "molecule", "compound", "reaction", "acid", "base", "chemical"],
        "computer science": ["algorithm", "program", "function", "variable", "data", "software", "binary"],
        "geography": ["climate", "region", "country", "population", "earthquake", "map", "environment"],
        "history": ["war", "revolution", "empire", "treaty", "century", "historical", "civilization"],
        "music": ["rhythm", "melody", "harmony", "tempo", "instrument", "composer"],
        "art": ["artist", "painting", "design", "composition", "color", "movement"]
    ]
}
