//
//  FlashcardAIEnhancer.swift
//  CA2ISOApp

import Foundation
import NaturalLanguage

struct FlashcardDeckMetadataSuggestion: Sendable {
    let title: String
    let studySubject: String
    let topic: String

    nonisolated init(title: String, studySubject: String, topic: String) {
        self.title = title
        self.studySubject = studySubject
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
        var usedConcepts = Set<String>()
        var styleCounts: [FlashcardPromptStyle: Int] = [:]
        var usedQuestionSignatures = Set<String>()

        for rankedDraft in rankedDrafts {
            let conceptAlreadyCovered = !rankedDraft.conceptKey.isEmpty && usedConcepts.contains(rankedDraft.conceptKey)
            let questionSignature = normalizedQuestionSignature(for: rankedDraft.draft.question)
            let repeatedQuestion = !questionSignature.isEmpty && usedQuestionSignatures.contains(questionSignature)
            let styleLimitReached = (styleCounts[rankedDraft.draft.style] ?? 0) >= 6

            if repeatedQuestion {
                continue
            }

            if conceptAlreadyCovered && rankedDraft.score < 84 {
                continue
            }

            if styleLimitReached && rankedDraft.score < 88 {
                continue
            }

            selectedDrafts.append(rankedDraft.draft)

            if !rankedDraft.conceptKey.isEmpty {
                usedConcepts.insert(rankedDraft.conceptKey)
            }

            if !questionSignature.isEmpty {
                usedQuestionSignatures.insert(questionSignature)
            }

            styleCounts[rankedDraft.draft.style, default: 0] += 1

            if selectedDrafts.count == 24 {
                break
            }
        }

        let minimumCount = min(12, rankedDrafts.count)
        if selectedDrafts.count < minimumCount {
            for rankedDraft in rankedDrafts where !selectedDrafts.contains(rankedDraft.draft) {
                selectedDrafts.append(rankedDraft.draft)
                if selectedDrafts.count == minimumCount {
                    break
                }
            }
        }

        return selectedDrafts
    }

    nonisolated static func suggestMetadata(
        from sourceText: String,
        fallbackTitle: String,
        availablestudySubjects: [String],
        preferredstudySubject: String,
        fallbackTopic: String
    ) -> FlashcardDeckMetadataSuggestion {
        let cleanedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceAnalysis = FlashcardSourceAnalyzer.analyze(cleanedText)
        let resolvedTopic = suggestTopic(
            from: cleanedText,
            fallbackTopic: fallbackTopic,
            sourceAnalysis: sourceAnalysis
        )
        let resolvedstudySubject = suggeststudySubject(
            from: cleanedText,
            availablestudySubjects: availablestudySubjects,
            preferredstudySubject: preferredstudySubject,
            fallbackTopic: resolvedTopic,
            sourceAnalysis: sourceAnalysis
        )
        let resolvedTitle = suggestTitle(
            fallbackTitle: fallbackTitle,
            topic: resolvedTopic,
            studySubject: resolvedstudySubject
        )

        return FlashcardDeckMetadataSuggestion(
            title: resolvedTitle,
            studySubject: resolvedstudySubject,
            topic: resolvedTopic
        )
    }

    nonisolated static func confidence(for draft: FlashcardDraft, sourceText: String) -> FlashcardConfidence {
        let cleanedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else { return draft.confidence }

        let anchors = conceptAnchors(in: cleanedText)
        let refinedDraft = refine(draft, sourceText: cleanedText, conceptAnchors: anchors)
        let draftScore = score(for: refinedDraft, sourceText: cleanedText, conceptAnchors: anchors)
        let evidence = bestEvidenceExcerpt(for: refinedDraft, sourceText: cleanedText)

        if draftScore >= 98 || (draftScore >= 92 && !evidence.isEmpty) {
            return .high
        }

        if draftScore >= 82 {
            return .medium
        }

        return .low
    }

    nonisolated static func bestEvidenceExcerpt(for draft: FlashcardDraft, sourceText: String) -> String {
        let cleanedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else { return cleanupSpacing(in: draft.evidenceExcerpt) }

        let anchors = conceptAnchors(in: cleanedText)
        let refinedDraft = refine(draft, sourceText: cleanedText, conceptAnchors: anchors)
        let relevantTokens = Set(tokens(in: "\(refinedDraft.question) \(refinedDraft.answer)"))
        guard !relevantTokens.isEmpty else { return cleanupSpacing(in: refinedDraft.evidenceExcerpt) }

        let strongestAnchor = bestConceptAnchor(for: refinedDraft, conceptAnchors: anchors)?.lowercased() ?? ""
        var bestMatch = ""
        var bestScore = 0

        for candidate in evidenceCandidates(from: cleanedText) {
            let candidateTokens = Set(tokens(in: candidate))
            guard !candidateTokens.isEmpty else { continue }

            let overlap = relevantTokens.intersection(candidateTokens).count
            guard overlap > 0 else { continue }

            var candidateScore = overlap * 8
            let loweredCandidate = candidate.lowercased()

            if !strongestAnchor.isEmpty, loweredCandidate.contains(strongestAnchor) {
                candidateScore += 18
            }

            if loweredCandidate.contains(normalizedComparisonText(refinedDraft.question)) {
                candidateScore += 8
            }

            if loweredCandidate.contains(normalizedComparisonText(refinedDraft.answer)) {
                candidateScore += 10
            }

            if candidate.count >= 40 && candidate.count <= 240 {
                candidateScore += 6
            } else {
                candidateScore -= 4
            }

            if candidateScore > bestScore {
                bestScore = candidateScore
                bestMatch = candidate
            }
        }

        if bestScore >= 12 {
            return trimmedEvidenceExcerpt(bestMatch)
        }

        return trimmedEvidenceExcerpt(refinedDraft.evidenceExcerpt)
    }

    private nonisolated static func refine(
        _ draft: FlashcardDraft,
        sourceText: String,
        conceptAnchors: [String]
    ) -> FlashcardDraft {
        let normalizedQuestion = cleanupSpacing(in: draft.question)
        let normalizedAnswer = cleanupSpacing(in: draft.answer)
        let strongestAnchor = bestConceptAnchor(for: draft, conceptAnchors: conceptAnchors)

        if isGenericSummaryQuestion(normalizedQuestion), let strongestAnchor {
            return FlashcardDraft(
                id: draft.id,
                question: "What are the key ideas in \(strongestAnchor)?",
                answer: normalizedAnswer,
                style: .summary,
                confidence: draft.confidence,
                evidenceExcerpt: draft.evidenceExcerpt
            )
        }

        if draft.style == .explanation,
           normalizedQuestion.lowercased().hasPrefix("explain "),
           normalizedQuestion.count > 70,
           let strongestAnchor {
            return FlashcardDraft(
                id: draft.id,
                question: "Explain \(strongestAnchor)",
                answer: normalizedAnswer,
                style: .explanation,
                confidence: draft.confidence,
                evidenceExcerpt: draft.evidenceExcerpt
            )
        }

        if draft.style == .how,
           normalizedQuestion.lowercased().hasPrefix("how does "),
           normalizedQuestion.lowercased().hasSuffix(" happen?"),
           let strongestAnchor {
            return FlashcardDraft(
                id: draft.id,
                question: "How does \(strongestAnchor) work?",
                answer: normalizedAnswer,
                style: .how,
                confidence: draft.confidence,
                evidenceExcerpt: draft.evidenceExcerpt
            )
        }

        if draft.style == .why,
           normalizedQuestion.lowercased().hasPrefix("why "),
           normalizedQuestion.hasSuffix("??"),
           let strongestAnchor {
            return FlashcardDraft(
                id: draft.id,
                question: "Why is \(strongestAnchor) important?",
                answer: normalizedAnswer,
                style: .why,
                confidence: draft.confidence,
                evidenceExcerpt: draft.evidenceExcerpt
            )
        }

        return FlashcardDraft(
            id: draft.id,
            question: normalizedQuestion,
            answer: normalizedAnswer,
            style: draft.style,
            confidence: draft.confidence,
            evidenceExcerpt: draft.evidenceExcerpt
        )
    }

    private nonisolated static func score(
        for draft: FlashcardDraft,
        sourceText: String,
        conceptAnchors: [String]
    ) -> Double {
        var total = baseScore(for: draft.style)

        let questionLength = draft.question.count
        let answerLength = draft.answer.count
        let loweredQuestion = draft.question.lowercased()
        let loweredAnswer = draft.answer.lowercased()

        if questionLength >= 10 && questionLength <= 110 {
            total += 14
        } else {
            total -= 10
        }

        if answerLength >= 18 && answerLength <= 240 {
            total += 16
        } else if answerLength <= 360 {
            total += 8
        } else {
            total -= 14
        }

        if startsWithSupportedQuestionStem(draft.question) {
            total += 10
        } else {
            total -= 12
        }

        if questionSpecificityScore(for: draft.question) >= 3 {
            total += 8
        }

        if answerSpecificityScore(for: draft.answer) >= 4 {
            total += 10
        }

        if conceptCoverageScore(for: draft, sourceText: sourceText, conceptAnchors: conceptAnchors) > 0 {
            total += 12
        }

        if draft.answer.contains("\n•") || draft.answer.contains("• ") {
            total += 8
        }

        if draft.answer.range(of: #"\n\d+[\.\)]\s+"#, options: .regularExpression) != nil {
            total += 8
        }

        if loweredAnswer.contains("because") && draft.style == .why {
            total += 7
        }

        if loweredQuestion.contains("compare") && containsComparisonLanguage(loweredAnswer) {
            total += 8
        }

        if loweredQuestion.contains("how ") && containsProcessLanguage(loweredAnswer) {
            total += 8
        }

        if loweredQuestion.contains("one key thing to remember")
            || loweredQuestion.contains("what should you know about")
            || loweredQuestion.contains("cover page")
            || loweredQuestion.contains("table of contents") {
            total -= 35
        }

        if looksLikeLowValueText(draft.question) || looksLikeLowValueText(draft.answer) {
            total -= 38
        }

        let overlap = lexicalOverlap(question: draft.question, answer: draft.answer)
        total -= overlap * 12

        return total
    }

    private nonisolated static func baseScore(for style: FlashcardPromptStyle) -> Double {
        switch style {
        case .definition:
            return 82
        case .explanation:
            return 78
        case .why:
            return 84
        case .how:
            return 83
        case .compare:
            return 85
        case .summary:
            return 74
        }
    }

    private nonisolated static func conceptCoverageScore(
        for draft: FlashcardDraft,
        sourceText: String,
        conceptAnchors: [String]
    ) -> Double {
        let loweredText = sourceText.lowercased()

        if let anchor = bestConceptAnchor(for: draft, conceptAnchors: conceptAnchors),
           loweredText.contains(anchor.lowercased()) {
            return 1
        }

        if let concept = strongestConcept(in: draft.question + " " + draft.answer),
           loweredText.contains(concept.lowercased()) {
            return 1
        }

        return 0
    }

    private nonisolated static func lexicalOverlap(question: String, answer: String) -> Double {
        let questionTokens = Set(tokens(in: question))
        let answerTokens = Set(tokens(in: answer))

        guard !questionTokens.isEmpty, !answerTokens.isEmpty else { return 0 }

        let intersection = questionTokens.intersection(answerTokens)
        return Double(intersection.count) / Double(max(questionTokens.count, 1))
    }

    private nonisolated static func questionSpecificityScore(for question: String) -> Int {
        Set(tokens(in: question)).count
    }

    private nonisolated static func answerSpecificityScore(for answer: String) -> Int {
        Set(tokens(in: answer)).count
    }

    private nonisolated static func conceptKey(for draft: FlashcardDraft, conceptAnchors: [String]) -> String {
        if let anchor = bestConceptAnchor(for: draft, conceptAnchors: conceptAnchors) {
            return anchor.lowercased()
        }

        if let concept = strongestConcept(in: draft.question) {
            return concept.lowercased()
        }

        if let concept = strongestConcept(in: draft.answer) {
            return concept.lowercased()
        }

        return ""
    }

    private nonisolated static func suggeststudySubject(
        from text: String,
        availablestudySubjects: [String],
        preferredstudySubject: String,
        fallbackTopic: String,
        sourceAnalysis: FlashcardSourceAnalysis
    ) -> String {
        let trimmedPreferredstudySubject = preferredstudySubject.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedstudySubjects = availablestudySubjects
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalizedstudySubjects.isEmpty else {
            return trimmedPreferredstudySubject
        }

        let loweredText = text.lowercased()
        let extractedKeywords = Set(
            tokens(
                in: text
                    + " "
                    + fallbackTopic
                    + " "
                    + sourceAnalysis.dominantConcepts.joined(separator: " ")
            )
        )

        let studySubjectScores = normalizedstudySubjects.map { studySubject in
            (
                studySubject: studySubject,
                score: studySubjectScore(
                    for: studySubject,
                    loweredText: loweredText,
                    extractedKeywords: extractedKeywords
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.studySubject < rhs.studySubject
            }
            return lhs.score > rhs.score
        }

        if let bestMatch = studySubjectScores.first, bestMatch.score >= 16 {
            return bestMatch.studySubject
        }

        if !trimmedPreferredstudySubject.isEmpty {
            return trimmedPreferredstudySubject
        }

        return studySubjectScores.first?.studySubject ?? normalizedstudySubjects.first ?? ""
    }

    private nonisolated static func studySubjectScore(
        for studySubject: String,
        loweredText: String,
        extractedKeywords: Set<String>
    ) -> Int {
        let normalizedstudySubject = studySubject.lowercased()
        var score = 0

        if loweredText.contains(normalizedstudySubject) {
            score += 44
        }

        for token in tokens(in: studySubject) where extractedKeywords.contains(token) {
            score += 24
        }

        for keyword in studySubjectKeywords[normalizedstudySubject, default: []] where loweredText.contains(keyword) {
            score += 9
        }

        return score
    }

    private nonisolated static func suggestTitle(
        fallbackTitle: String,
        topic: String,
        studySubject: String
    ) -> String {
        let trimmedTitle = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedstudySubject = studySubject.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedTitle.isEmpty && !isGenericTitle(trimmedTitle) {
            return trimmedTitle
        }

        if !trimmedTopic.isEmpty && !trimmedstudySubject.isEmpty {
            return "\(trimmedTopic) • \(trimmedstudySubject)"
        }

        if !trimmedTopic.isEmpty {
            return "\(trimmedTopic) Flashcards"
        }

        if !trimmedstudySubject.isEmpty {
            return "\(trimmedstudySubject) Flashcards"
        }

        return "Smart Flashcards"
    }

    private nonisolated static func suggestTopic(
        from text: String,
        fallbackTopic: String,
        sourceAnalysis: FlashcardSourceAnalysis
    ) -> String {
        let trimmedTopic = fallbackTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTopic.isEmpty {
            return trimmedTopic
        }

        if let sectionTitle = sourceAnalysis.sections.first?.title {
            return sectionTitle
        }

        if let dominantConcept = sourceAnalysis.dominantConcepts.first {
            return dominantConcept
        }

        let headings = sourceHeadings(from: text)
        if let heading = headings.first(where: isLikelyHeading) {
            return heading
        }

        if let repeatedAnchor = conceptAnchors(in: text).first {
            return repeatedAnchor
        }

        return strongestConcept(in: text) ?? ""
    }

    private nonisolated static func sourceHeadings(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { isLikelyHeading($0) }
    }

    private nonisolated static func conceptAnchors(in text: String) -> [String] {
        let loweredText = text.lowercased()
        let tokenCounts = tokens(in: text).reduce(into: [String: Int]()) { partialResult, token in
            partialResult[token, default: 0] += 1
        }

        let repeatedTokens = tokenCounts
            .filter { $0.value >= 2 && $0.key.count > 3 }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.count > rhs.key.count
                }
                return lhs.value > rhs.value
            }
            .map(\.key)

        var anchors: [String] = []

        for heading in sourceHeadings(from: text) where !anchors.contains(heading) {
            anchors.append(heading)
            if anchors.count == 5 {
                break
            }
        }

        for token in repeatedTokens where loweredText.contains(token) && !anchors.contains(where: { $0.lowercased() == token }) {
            anchors.append(token.capitalized)
            if anchors.count == 10 {
                break
            }
        }

        if anchors.isEmpty, let concept = strongestConcept(in: text) {
            anchors.append(concept)
        }

        return anchors
    }

    private nonisolated static func bestConceptAnchor(
        for draft: FlashcardDraft,
        conceptAnchors: [String]
    ) -> String? {
        let loweredCombined = "\(draft.question) \(draft.answer)".lowercased()

        if let exactAnchor = conceptAnchors.first(where: { loweredCombined.contains($0.lowercased()) }) {
            return exactAnchor
        }

        if let concept = strongestConcept(in: draft.question + " " + draft.answer) {
            return concept
        }

        return nil
    }

    private nonisolated static func evidenceCandidates(from text: String) -> [String] {
        let paragraphCandidates = text
            .components(separatedBy: "\n\n")
            .map { normalizeText($0) }
            .filter(isUsefulEvidenceCandidate)

        let lineCandidates = text
            .components(separatedBy: .newlines)
            .map { cleanupSpacing(in: $0) }
            .filter(isUsefulEvidenceCandidate)

        let sentenceTokenizer = NLTokenizer(unit: .sentence)
        sentenceTokenizer.string = text

        var sentenceCandidates: [String] = []
        sentenceTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = cleanupSpacing(in: String(text[range]))
            if isUsefulEvidenceCandidate(sentence) {
                sentenceCandidates.append(sentence)
            }
            return true
        }

        var uniqueCandidates: [String] = []
        var seen = Set<String>()

        for candidate in paragraphCandidates + sentenceCandidates + lineCandidates {
            let normalizedCandidate = normalizedComparisonText(candidate)
            guard !normalizedCandidate.isEmpty, !seen.contains(normalizedCandidate) else { continue }

            seen.insert(normalizedCandidate)
            uniqueCandidates.append(candidate)

            if uniqueCandidates.count == 36 {
                break
            }
        }

        return uniqueCandidates
    }

    private nonisolated static func isUsefulEvidenceCandidate(_ text: String) -> Bool {
        let cleanedText = cleanupSpacing(in: text)
        guard cleanedText.count >= 30 else { return false }
        guard !looksLikeLowValueText(cleanedText) else { return false }
        return true
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

    private nonisolated static func cleanupSpacing(in text: String) -> String {
        text
            .replacingOccurrences(of: "  ", with: " ")
            .replacingOccurrences(of: "?.", with: "?")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func normalizeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { cleanupSpacing(in: String($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private nonisolated static func normalizedComparisonText(_ text: String) -> String {
        cleanupSpacing(in: text)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private nonisolated static func trimmedEvidenceExcerpt(_ text: String) -> String {
        let cleanedText = cleanupSpacing(in: text)
        guard cleanedText.count > 220 else { return cleanedText }

        let prefixText = cleanedText.prefix(217)
        return "\(prefixText)..."
    }

    private nonisolated static func normalizedQuestionSignature(for question: String) -> String {
        tokens(in: question).joined(separator: " ")
    }

    private nonisolated static func isGenericSummaryQuestion(_ question: String) -> Bool {
        let loweredQuestion = question.lowercased()
        return loweredQuestion.contains("one key thing to remember about")
            || loweredQuestion.contains("what should you know about")
            || loweredQuestion == "explain this topic"
    }

    private nonisolated static func isGenericTitle(_ title: String) -> Bool {
        let genericTitles = [
            "photo flashcards",
            "pasted notes",
            "smart flashcards",
            "manual flashcards",
            "imported file"
        ]

        return genericTitles.contains(title.lowercased())
    }

    private nonisolated static func startsWithSupportedQuestionStem(_ question: String) -> Bool {
        let loweredQuestion = question.lowercased()
        let stems = ["what ", "how ", "why ", "explain ", "compare "]
        return stems.contains(where: { loweredQuestion.hasPrefix($0) })
    }

    private nonisolated static func containsComparisonLanguage(_ text: String) -> Bool {
        let markers = ["whereas", "unlike", "however", "in contrast", "on the other hand"]
        return markers.contains(where: { text.contains($0) })
    }

    private nonisolated static func containsProcessLanguage(_ text: String) -> Bool {
        let markers = ["first", "next", "then", "finally", "step", "process"]
        return markers.contains(where: { text.contains($0) })
    }

    private nonisolated static func isLikelyHeading(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        return text.count <= 45
            && words.count <= 6
            && !text.contains("?")
            && !text.contains(":")
            && !looksLikeLowValueText(text)
    }

    private nonisolated static func isUsefulKeyword(_ token: String) -> Bool {
        !stopWords.contains(token.lowercased())
    }

    private nonisolated static func looksLikeLowValueText(_ text: String) -> Bool {
        let cleanedText = cleanupSpacing(in: text)
        let loweredText = text.lowercased()
        let blockedTerms = [
            "table of contents", "contents", "student name", "student number",
            "module code", "copyright", "references", "bibliography",
            "acknowledgements", "submitted by", "prepared by", "assignment",
            "learning outcomes", "appendix", "overview", "university",
            "istockphoto", "alamy", "shutterstock", "getty", "image credit",
            "photo credit", "photo by", "image by", "cover image", "cover design",
            "illustration by", "all rights reserved", "dedicated to",
            "in memory of", "father, lumberman, and friend",
            "review questions", "discussion questions", "chapter objectives",
            "learning objectives"
        ]
        let titleCaseNamePattern = #"^[A-Z][a-z]+(?:\s+[A-Z][a-z]+){2,3}$"#

        return blockedTerms.contains(where: { loweredText.contains($0) })
            || (cleanedText.range(of: titleCaseNamePattern, options: .regularExpression) != nil
                && cleanedText.count <= 50
                && looksLikeShortPersonCredit(cleanedText))
    }

    private nonisolated static func looksLikeShortPersonCredit(_ text: String) -> Bool {
        let commonFirstNames: Set<String> = [
            "peter", "joseph", "william", "john", "mary", "james", "robert",
            "michael", "david", "richard", "charles", "thomas", "christopher",
            "daniel", "paul", "mark", "george", "susan", "sarah", "elizabeth"
        ]
        let loweredWords = text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }

        return loweredWords.contains(where: { commonFirstNames.contains($0) })
    }

    private nonisolated static let stopWords: Set<String> = [
        "the", "and", "with", "from", "that", "this", "these", "those",
        "have", "has", "had", "into", "their", "there", "which", "what",
        "when", "where", "whose", "your", "about", "because", "through",
        "using", "used", "also", "than", "then", "them", "they", "will",
        "shall", "could", "would", "should", "into", "onto", "each", "such"
    ]

    private nonisolated static let studySubjectKeywords: [String: [String]] = [
        "english": ["poem", "poetry", "novel", "theme", "character", "language", "essay", "author", "drama", "imagery"],
        "french": ["french", "bonjour", "verb", "grammar", "vocabulary", "translation", "tense"],
        "german": ["german", "verb", "grammar", "vocabulary", "translation", "tense"],
        "spanish": ["spanish", "verb", "grammar", "vocabulary", "translation", "tense"],
        "mathematics": ["equation", "algebra", "geometry", "graph", "theorem", "calculus", "probability", "function"],
        "maths": ["equation", "algebra", "geometry", "graph", "theorem", "calculus", "probability", "function"],
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
