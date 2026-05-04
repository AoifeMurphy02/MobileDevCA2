//
//  FlashcardAIEnhancer.swift
//  CA2ISOApp

import Foundation
import NaturalLanguage

struct FlashcardDeckMetadataSuggestion: Sendable {
    let title: String
    let studyArea: String
    let topic: String

    nonisolated init(title: String, studyArea: String, topic: String) {
        self.title = title
        self.studyArea = studyArea
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
        guard !cleanedText.isEmpty, !drafts.isEmpty else { return [] }

        let conceptAnchors = conceptAnchors(in: cleanedText)

        let rankedDrafts = drafts.map { draft in
            let refinedDraft = refine(draft, sourceText: cleanedText, conceptAnchors: conceptAnchors)
            return RankedFlashcardDraft(
                draft: refinedDraft,
                score: score(for: refinedDraft, sourceText: cleanedText, conceptAnchors: conceptAnchors),
                conceptKey: conceptKey(for: refinedDraft, conceptAnchors: conceptAnchors)
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.draft.question.count < rhs.draft.question.count
            }
            return lhs.score > rhs.score
        }

        var selectedDrafts: [FlashcardDraft] = []
        var usedQuestionSignatures = Set<String>()

        for rankedDraft in rankedDrafts {
            let questionSignature = normalizedQuestionSignature(for: rankedDraft.draft.question)
            if usedQuestionSignatures.contains(questionSignature) { continue }
            
            selectedDrafts.append(rankedDraft.draft)
            usedQuestionSignatures.insert(questionSignature)

            if selectedDrafts.count == 24 { break }
        }

        return selectedDrafts
    }

    nonisolated static func suggestMetadata(
        from sourceText: String,
        fallbackTitle: String,
        availablestudyAreas: [String],
        preferredstudyArea: String,
        fallbackTopic: String
    ) -> FlashcardDeckMetadataSuggestion {
        let cleanedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceAnalysis = FlashcardSourceAnalyzer.analyze(cleanedText)
        let resolvedTopic = suggestTopic(from: cleanedText, fallbackTopic: fallbackTopic, sourceAnalysis: sourceAnalysis)
        
        let resolvedstudyArea = suggeststudyArea(
            from: cleanedText,
            availablestudyAreas: availablestudyAreas,
            preferredstudyArea: preferredstudyArea,
            fallbackTopic: resolvedTopic,
            sourceAnalysis: sourceAnalysis
        )
        
        let resolvedTitle = suggestTitle(
            fallbackTitle: fallbackTitle,
            topic: resolvedTopic,
            studyArea: resolvedstudyArea
        )

        return FlashcardDeckMetadataSuggestion(
            title: resolvedTitle,
            studyArea: resolvedstudyArea,
            topic: resolvedTopic
        )
    }

    nonisolated static func confidence(for draft: FlashcardDraft, sourceText: String) -> FlashcardConfidence {
        let cleanedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else { return draft.confidence }
        let scoreValue = score(for: draft, sourceText: cleanedText, conceptAnchors: conceptAnchors(in: cleanedText))
        if scoreValue >= 92 { return .high }
        if scoreValue >= 82 { return .medium }
        return .low
    }

    nonisolated static func bestEvidenceExcerpt(for draft: FlashcardDraft, sourceText: String) -> String {
        return trimmedEvidenceExcerpt(draft.evidenceExcerpt)
    }

    private nonisolated static func suggeststudyArea(
        from text: String,
        availablestudyAreas: [String],
        preferredstudyArea: String,
        fallbackTopic: String,
        sourceAnalysis: FlashcardSourceAnalysis
    ) -> String {
        let normalizedList = availablestudyAreas.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !normalizedList.isEmpty else { return preferredstudyArea }

        let loweredText = text.lowercased()
        let extractedKeywords = Set(tokens(in: text + " " + fallbackTopic))

        let studyAreaScores = normalizedList.map { name in
            (
                studyArea: name,
                score: studyAreaScore(for: name, loweredText: loweredText, extractedKeywords: extractedKeywords)
            )
        }
        .sorted { $0.score > $1.score }

        if let bestMatch = studyAreaScores.first, bestMatch.score >= 16 {
            return bestMatch.studyArea
        }

        return !preferredstudyArea.isEmpty ? preferredstudyArea : (studyAreaScores.first?.studyArea ?? "General")
    }

    private nonisolated static func studyAreaScore(for name: String, loweredText: String, extractedKeywords: Set<String>) -> Int {
        let normalized = name.lowercased()
        var score = 0
        if loweredText.contains(normalized) { score += 44 }
        for token in tokens(in: name) where extractedKeywords.contains(token) { score += 24 }
        
        // Match against the keywords list at the bottom
        for keyword in studyAreaKeywords[normalized, default: []] where loweredText.contains(keyword) {
            score += 9
        }
        return score
    }

    private nonisolated static func suggestTitle(fallbackTitle: String, topic: String, studyArea: String) -> String {
        let trimmedTitle = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty && !isGenericTitle(trimmedTitle) { return trimmedTitle }
        if !topic.isEmpty && !studyArea.isEmpty { return "\(topic) • \(studyArea)" }
        return topic.isEmpty ? "Smart Flashcards" : "\(topic) Flashcards"
    }

    // MARK: - Internal Helpers

    private nonisolated static func conceptAnchors(in text: String) -> [String] {
        return tokens(in: text).prefix(10).map { $0.capitalized }
    }

    private nonisolated static func bestConceptAnchor(for draft: FlashcardDraft, conceptAnchors: [String]) -> String? {
        let combined = "\(draft.question) \(draft.answer)".lowercased()
        return conceptAnchors.first(where: { combined.contains($0.lowercased()) })
    }

    private nonisolated static func strongestConcept(in text: String) -> String? {
        let tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass])
        tagger.string = text
        var candidates: [String: Int] = [:]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameTypeOrLexicalClass, options: [.omitWhitespace]) { tag, range in
            let token = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if token.count > 2 { candidates[token, default: 0] += 1 }
            return true
        }
        return candidates.sorted { $0.value > $1.value }.first?.key
    }

    private nonisolated static func tokens(in text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 }
    }

    private nonisolated static func cleanupSpacing(in text: String) -> String {
        text.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func normalizeText(_ text: String) -> String {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private nonisolated static func normalizedComparisonText(_ text: String) -> String {
        cleanupSpacing(in: text).lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private nonisolated static func trimmedEvidenceExcerpt(_ text: String) -> String {
        let cleaned = cleanupSpacing(in: text)
        return cleaned.count > 220 ? "\(cleaned.prefix(217))..." : cleaned
    }

    private nonisolated static func normalizedQuestionSignature(for question: String) -> String { tokens(in: question).joined(separator: " ") }

    private nonisolated static func isGenericSummaryQuestion(_ question: String) -> Bool {
        let low = question.lowercased()
        return low.contains("remember about") || low.contains("should you know")
    }

    private nonisolated static func isGenericTitle(_ title: String) -> Bool {
        ["smart flashcards", "manual flashcards", "imported file"].contains(title.lowercased())
    }

    private nonisolated static func startsWithSupportedQuestionStem(_ question: String) -> Bool {
        let low = question.lowercased()
        return ["what ", "how ", "why ", "explain ", "compare "].contains(where: { low.hasPrefix($0) })
    }

    private nonisolated static func isLikelyHeading(_ text: String) -> Bool {
        return text.count <= 45 && text.split(separator: " ").count <= 6 && !text.contains("?")
    }

    private nonisolated static func suggestTopic(from text: String, fallbackTopic: String, sourceAnalysis: FlashcardSourceAnalysis) -> String {
        if !fallbackTopic.isEmpty { return fallbackTopic }
        return sourceAnalysis.dominantConcepts.first ?? "General Topic"
    }

    private nonisolated static func refine(_ draft: FlashcardDraft, sourceText: String, conceptAnchors: [String]) -> FlashcardDraft {
        return draft
    }

    private nonisolated static func score(for draft: FlashcardDraft, sourceText: String, conceptAnchors: [String]) -> Double {
        return 85.0
    }

    private nonisolated static func conceptKey(for draft: FlashcardDraft, conceptAnchors: [String]) -> String {
        return bestConceptAnchor(for: draft, conceptAnchors: conceptAnchors) ?? ""
    }

    private nonisolated static func looksLikeLowValueText(_ text: String) -> Bool {
        return text.lowercased().contains("copyright")
    }

    private nonisolated static let studyAreaKeywords: [String: [String]] = [
        "english": ["poem", "poetry", "novel", "theme", "character", "language", "essay", "author", "drama", "imagery"],
        "mathematics": ["equation", "algebra", "geometry", "graph", "theorem", "calculus", "probability", "function"],
        "physics": ["force", "velocity", "motion", "energy", "acceleration", "gravity", "mass", "wave", "momentum"],
        "biology": ["cell", "organism", "photosynthesis", "ecosystem", "gene", "protein", "enzyme", "respiration"],
        "chemistry": ["atom", "molecule", "compound", "reaction", "acid", "base", "chemical", "bond", "electron"],
        "computer science": ["algorithm", "program", "function", "variable", "data", "software", "binary", "network", "database"],
        "geography": ["climate", "region", "country", "population", "earthquake", "map", "environment", "urban", "river"],
        "history": ["war", "revolution", "empire", "treaty", "century", "historical", "civilization", "monarch", "reform"],
        "music": ["rhythm", "melody", "harmony", "tempo", "instrument", "composer", "dynamics", "pitch"],
        "art": ["artist", "painting", "design", "composition", "color", "movement", "texture", "portrait"],
        "business": ["market", "finance", "management", "revenue", "strategy", "consumer", "supply"],
        "economics": ["demand", "supply", "inflation", "market", "economy", "cost", "elasticity"],
        "psychology": ["behavior", "memory", "cognition", "emotion", "brain", "learning", "therapy"]
    ]
}
