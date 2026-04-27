//
//  FlashcardSourceAnalyzer.swift
//  CA2ISOApp
//
//  Created by Meghana on 18/04/2026.
//

import Foundation
import NaturalLanguage

struct FlashcardSourceSection: Sendable {
    let title: String
    let body: String
    let concepts: [String]

    nonisolated init(title: String, body: String, concepts: [String]) {
        self.title = title
        self.body = body
        self.concepts = concepts
    }
}

struct FlashcardSourceAnalysis: Sendable {
    let sections: [FlashcardSourceSection]
    let dominantConcepts: [String]
    let suggestedDrafts: [FlashcardDraft]

    nonisolated init(
        sections: [FlashcardSourceSection],
        dominantConcepts: [String],
        suggestedDrafts: [FlashcardDraft]
    ) {
        self.sections = sections
        self.dominantConcepts = dominantConcepts
        self.suggestedDrafts = suggestedDrafts
    }
}

enum FlashcardSourceAnalyzer {
    nonisolated static func analyze(_ text: String) -> FlashcardSourceAnalysis {
        let normalizedText = normalizeText(text)
        guard !normalizedText.isEmpty else {
            return FlashcardSourceAnalysis(
                sections: [],
                dominantConcepts: [],
                suggestedDrafts: []
            )
        }

        let sections = extractedSections(from: normalizedText)
        let dominantConcepts = conceptCandidates(in: normalizedText, limit: 8)

        var drafts = sectionDrafts(from: sections)
        drafts.append(contentsOf: comparisonDrafts(from: sections))
        drafts.append(contentsOf: relationshipDrafts(from: normalizedText, dominantConcepts: dominantConcepts))

        return FlashcardSourceAnalysis(
            sections: sections,
            dominantConcepts: dominantConcepts,
            suggestedDrafts: Array(drafts.prefix(14))
        )
    }

    private nonisolated static func extractedSections(from text: String) -> [FlashcardSourceSection] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let headingSections = headingBasedSections(from: lines)
        if !headingSections.isEmpty {
            return balancedSections(from: headingSections, maximumCount: 24)
        }

        return balancedSections(from: chunkedSections(from: lines), maximumCount: 20)
    }

    private nonisolated static func headingBasedSections(from lines: [String]) -> [FlashcardSourceSection] {
        var sections: [FlashcardSourceSection] = []
        var currentTitle: String?
        var currentLines: [String] = []

        func flushSection() {
            guard let section = makeSection(title: currentTitle, lines: currentLines) else {
                currentTitle = nil
                currentLines = []
                return
            }

            sections.append(section)
            currentTitle = nil
            currentLines = []
        }

        for line in lines {
            if isLikelyHeading(line) {
                flushSection()
                currentTitle = line
                continue
            }

            guard currentTitle != nil else { continue }
            guard !looksLikeStructuralText(line) else { continue }

            currentLines.append(line)

            if currentLines.joined(separator: " ").count > 620 {
                flushSection()
            }
        }

        flushSection()
        return sections
    }

    private nonisolated static func chunkedSections(from lines: [String]) -> [FlashcardSourceSection] {
        var sections: [FlashcardSourceSection] = []
        var bucket: [String] = []

        func flushChunk() {
            guard let section = makeSection(title: nil, lines: bucket) else {
                bucket = []
                return
            }

            sections.append(section)
            bucket = []
        }

        for line in lines where !looksLikeStructuralText(line) && !isLikelyHeading(line) {
            bucket.append(line)

            if bucket.count == 5 || bucket.joined(separator: " ").count > 620 {
                flushChunk()
            }
        }

        flushChunk()
        return sections
    }

    private nonisolated static func makeSection(title: String?, lines: [String]) -> FlashcardSourceSection? {
        let body = normalizeText(lines.joined(separator: "\n"))
        guard body.count > 35 else { return nil }

        guard let resolvedTitle = normalizedSectionTitle(title: title, body: body) else {
            return nil
        }

        return FlashcardSourceSection(
            title: resolvedTitle,
            body: body,
            concepts: conceptCandidates(in: "\(resolvedTitle)\n\(body)", limit: 3)
        )
    }

    private nonisolated static func sectionDrafts(from sections: [FlashcardSourceSection]) -> [FlashcardDraft] {
        balancedSections(from: sections, maximumCount: 12).compactMap { section in
            let answer = compressedAnswer(
                from: section.body,
                maximumSentences: 3,
                maximumCharacters: 260
            )
            guard answer.count > 30 else { return nil }

            let prompt = sectionPrompt(for: section)
            return FlashcardDraft(
                question: prompt.question,
                answer: answer,
                style: prompt.style
            )
        }
    }

    private nonisolated static func comparisonDrafts(from sections: [FlashcardSourceSection]) -> [FlashcardDraft] {
        guard sections.count >= 2 else { return [] }

        var drafts: [FlashcardDraft] = []
        let selectedSections = balancedSections(from: sections, maximumCount: 10)

        for index in 0..<(selectedSections.count - 1) {
            let currentSection = selectedSections[index]
            let nextSection = selectedSections[index + 1]

            guard currentSection.title.lowercased() != nextSection.title.lowercased() else { continue }

            let leftSummary = shortSummary(from: currentSection.body)
            let rightSummary = shortSummary(from: nextSection.body)
            guard !leftSummary.isEmpty, !rightSummary.isEmpty else { continue }

            drafts.append(
                FlashcardDraft(
                    question: "How does \(currentSection.title) compare with \(nextSection.title)?",
                    answer: """
                    • \(currentSection.title): \(leftSummary)
                    • \(nextSection.title): \(rightSummary)
                    """,
                    style: .compare
                )
            )

            if drafts.count == 2 {
                break
            }
        }

        return drafts
    }

    private nonisolated static func relationshipDrafts(
        from text: String,
        dominantConcepts: [String]
    ) -> [FlashcardDraft] {
        Array(
            balancedSentences(from: splitSentences(text), maximumCount: 64)
                .compactMap { sentence in
                    draftFromRelationshipSentence(sentence, dominantConcepts: dominantConcepts)
                }
                .prefix(8)
        )
    }

    private nonisolated static func draftFromRelationshipSentence(
        _ sentence: String,
        dominantConcepts: [String]
    ) -> FlashcardDraft? {
        if let draft = exampleDraft(from: sentence, dominantConcepts: dominantConcepts) {
            return draft
        }

        if let draft = relationshipDraft(
            from: sentence,
            marker: " causes ",
            dominantConcepts: dominantConcepts,
            style: .why,
            question: { "What does \($0) cause?" }
        ) {
            return draft
        }

        if let draft = relationshipDraft(
            from: sentence,
            marker: " leads to ",
            dominantConcepts: dominantConcepts,
            style: .why,
            question: { "What does \($0) lead to?" }
        ) {
            return draft
        }

        if let draft = relationshipDraft(
            from: sentence,
            marker: " results in ",
            dominantConcepts: dominantConcepts,
            style: .why,
            question: { "What does \($0) result in?" }
        ) {
            return draft
        }

        if let draft = relationshipDraft(
            from: sentence,
            marker: " consists of ",
            dominantConcepts: dominantConcepts,
            style: .definition,
            question: { "What does \($0) consist of?" }
        ) {
            return draft
        }

        if let draft = relationshipDraft(
            from: sentence,
            marker: " includes ",
            dominantConcepts: dominantConcepts,
            style: .definition,
            question: { "What does \($0) include?" }
        ) {
            return draft
        }

        if let draft = relationshipDraft(
            from: sentence,
            marker: " contains ",
            dominantConcepts: dominantConcepts,
            style: .definition,
            question: { "What does \($0) contain?" }
        ) {
            return draft
        }

        if let draft = importanceDraft(from: sentence, dominantConcepts: dominantConcepts) {
            return draft
        }

        return nil
    }

    private nonisolated static func relationshipDraft(
        from sentence: String,
        marker: String,
        dominantConcepts: [String],
        style: FlashcardPromptStyle,
        question: (String) -> String
    ) -> FlashcardDraft? {
        guard let range = sentence.range(of: marker, options: [.caseInsensitive]) else {
            return nil
        }

        let subjectClause = String(sentence[..<range.lowerBound])
        let detailClause = String(sentence[range.upperBound...])

        guard let concept = conceptPhrase(from: subjectClause, dominantConcepts: dominantConcepts) else {
            return nil
        }

        let answer = compressedAnswer(from: detailClause, maximumSentences: 2, maximumCharacters: 200)
        guard answer.count > 12 else { return nil }

        return FlashcardDraft(
            question: question(concept),
            answer: answer,
            style: style
        )
    }

    private nonisolated static func importanceDraft(
        from sentence: String,
        dominantConcepts: [String]
    ) -> FlashcardDraft? {
        guard let range = sentence.range(of: " is important because ", options: [.caseInsensitive]) else {
            return nil
        }

        let subjectClause = String(sentence[..<range.lowerBound])
        let reasonClause = String(sentence[range.upperBound...])

        guard let concept = conceptPhrase(from: subjectClause, dominantConcepts: dominantConcepts) else {
            return nil
        }

        let reason = cleanupSpacing(in: reasonClause.trimmingCharacters(in: CharacterSet(charactersIn: ". ")))
        guard reason.count > 12 else { return nil }

        return FlashcardDraft(
            question: "Why is \(concept) important?",
            answer: "Because \(reason).",
            style: .why
        )
    }

    private nonisolated static func exampleDraft(
        from sentence: String,
        dominantConcepts: [String]
    ) -> FlashcardDraft? {
        let markers = [" such as ", " including ", " for example "]

        for marker in markers {
            guard let range = sentence.range(of: marker, options: [.caseInsensitive]) else {
                continue
            }

            let subjectClause = String(sentence[..<range.lowerBound])
            let examplesClause = String(sentence[range.upperBound...])

            guard let concept = conceptPhrase(from: subjectClause, dominantConcepts: dominantConcepts) else {
                continue
            }

            let examples = extractedExamples(from: examplesClause)
            let answer = examples.isEmpty
                ? compressedAnswer(from: examplesClause, maximumSentences: 1, maximumCharacters: 180)
                : examples
                    .prefix(4)
                    .map { "• \($0)" }
                    .joined(separator: "\n")

            guard answer.count > 12 else { continue }

            return FlashcardDraft(
                question: "What are examples of \(concept)?",
                answer: answer,
                style: .definition
            )
        }

        return nil
    }

    private nonisolated static func sectionPrompt(
        for section: FlashcardSourceSection
    ) -> (question: String, style: FlashcardPromptStyle) {
        let loweredBody = section.body.lowercased()

        if containsProcessLanguage(loweredBody) {
            return ("How does \(section.title) work?", .how)
        }

        if containsCauseLanguage(loweredBody) {
            return ("Why is \(section.title) important?", .why)
        }

        if looksDefinitionLike(section.body), section.title.split(separator: " ").count <= 5 {
            return ("What is \(section.title)?", .definition)
        }

        return ("Explain \(section.title)", .explanation)
    }

    private nonisolated static func conceptPhrase(
        from clause: String,
        dominantConcepts: [String]
    ) -> String? {
        let cleanedClause = cleanupLeadClause(clause)
        guard !cleanedClause.isEmpty else {
            return dominantConcepts.first(where: isReasonableConceptPhrase)
        }

        let wordCount = cleanedClause.split(separator: " ").count
        if wordCount <= 6
            && !cleanedClause.contains(",")
            && lettersRatio(in: cleanedClause) > 0.55
            && isReasonableConceptPhrase(cleanedClause) {
            return cleanedClause
        }

        if let matchedConcept = dominantConcepts.first(where: {
            cleanedClause.lowercased().contains($0.lowercased())
        }), isReasonableConceptPhrase(matchedConcept) {
            return matchedConcept
        }

        return conceptCandidates(in: cleanedClause, limit: 3).first(where: isReasonableConceptPhrase)
    }

    private nonisolated static func cleanupLeadClause(_ clause: String) -> String {
        var cleanedClause = cleanupSpacing(
            in: clause.trimmingCharacters(in: CharacterSet(charactersIn: ".:,; "))
        )

        let prefixes = [
            "a ", "an ", "the ", "this ", "these ", "those ",
            "to ", "for ", "of ", "in ", "on ", "by ", "from "
        ]
        for prefix in prefixes where cleanedClause.lowercased().hasPrefix(prefix) {
            cleanedClause = String(cleanedClause.dropFirst(prefix.count))
            break
        }

        return cleanupSpacing(in: cleanedClause)
    }

    private nonisolated static func normalizedSectionTitle(title: String?, body: String) -> String? {
        let bodyCandidates = conceptCandidates(in: body, limit: 4).map(cleanupLeadClause)
        let cleanedTitle = title.map(cleanupLeadClause)

        if let cleanedTitle,
           isReasonableConceptPhrase(cleanedTitle),
           cleanedTitle.split(separator: " ").count >= 2 {
            return cleanedTitle
        }

        if let richerBodyCandidate = bodyCandidates.first(where: {
            isReasonableConceptPhrase($0) && $0.split(separator: " ").count >= 2
        }) {
            return richerBodyCandidate
        }

        if let cleanedTitle, isReasonableConceptPhrase(cleanedTitle) {
            return cleanedTitle
        }

        for candidate in bodyCandidates where isReasonableConceptPhrase(candidate) {
            return candidate
        }

        return nil
    }

    private nonisolated static func balancedSections(
        from sections: [FlashcardSourceSection],
        maximumCount: Int
    ) -> [FlashcardSourceSection] {
        guard sections.count > maximumCount else { return sections }

        var selected: [FlashcardSourceSection] = []
        var usedIndexes = Set<Int>()
        let bucketCount = min(maximumCount, 6)

        for bucketIndex in 0..<bucketCount {
            let startIndex = bucketIndex * sections.count / bucketCount
            let endIndex = (bucketIndex + 1) * sections.count / bucketCount
            let bucketIndexes = Array(startIndex..<endIndex)

            guard let bestIndex = bucketIndexes.max(by: {
                sectionScore(sections[$0]) < sectionScore(sections[$1])
            }) else {
                continue
            }

            selected.append(sections[bestIndex])
            usedIndexes.insert(bestIndex)
        }

        let remainingIndexes = sections.indices
            .filter { !usedIndexes.contains($0) }
            .sorted {
                sectionScore(sections[$0]) > sectionScore(sections[$1])
            }

        for index in remainingIndexes {
            guard selected.count < maximumCount else { break }
            selected.append(sections[index])
        }

        return selected.sorted { lhs, rhs in
            guard let lhsIndex = sections.firstIndex(where: { $0.title == lhs.title && $0.body == lhs.body }),
                  let rhsIndex = sections.firstIndex(where: { $0.title == rhs.title && $0.body == rhs.body }) else {
                return lhs.title < rhs.title
            }

            return lhsIndex < rhsIndex
        }
    }

    private nonisolated static func sectionScore(_ section: FlashcardSourceSection) -> Int {
        let conceptCount = Set(tokens(in: "\(section.title) \(section.body)")).count
        let bodyLengthScore = min(section.body.count / 40, 10)
        let definitionScore = looksDefinitionLike(section.body) ? 8 : 0
        let processScore = containsProcessLanguage(section.body.lowercased()) ? 6 : 0
        let causeScore = containsCauseLanguage(section.body.lowercased()) ? 6 : 0

        return conceptCount * 3 + bodyLengthScore + definitionScore + processScore + causeScore
    }

    private nonisolated static func balancedSentences(
        from sentences: [String],
        maximumCount: Int
    ) -> [String] {
        guard sentences.count > maximumCount else { return sentences }

        var selectedIndexes = Set<Int>()
        var selected: [Int] = []
        let bucketCount = min(maximumCount, 6)

        for bucketIndex in 0..<bucketCount {
            let startIndex = bucketIndex * sentences.count / bucketCount
            let endIndex = (bucketIndex + 1) * sentences.count / bucketCount
            let bucketIndexes = Array(startIndex..<endIndex)

            guard let bestIndex = bucketIndexes.max(by: {
                sentencePriorityScore(for: sentences[$0]) < sentencePriorityScore(for: sentences[$1])
            }) else {
                continue
            }

            selected.append(bestIndex)
            selectedIndexes.insert(bestIndex)
        }

        let remainingIndexes = sentences.indices
            .filter { !selectedIndexes.contains($0) }
            .sorted {
                sentencePriorityScore(for: sentences[$0]) > sentencePriorityScore(for: sentences[$1])
            }

        for index in remainingIndexes {
            guard selected.count < maximumCount else { break }
            selected.append(index)
        }

        return selected.sorted().map { sentences[$0] }
    }

    private nonisolated static func isReasonableConceptPhrase(_ text: String) -> Bool {
        let cleanedText = cleanupLeadClause(text)
        let loweredText = cleanedText.lowercased()
        let words = loweredText
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let blockedGenericConcepts: Set<String> = [
            "properties", "property", "differences", "difference", "expression", "expressions",
            "material", "materials", "item", "items", "thing", "things", "example", "examples",
            "chapter", "introduction", "section", "problem", "problems", "equation", "equations",
            "process", "processes", "function", "functions", "system", "systems", "type", "types"
        ]

        let blockedEdgeWords: Set<String> = [
            "a", "an", "the", "to", "for", "of", "in", "on", "by", "from",
            "with", "and", "or", "each", "every", "this", "that", "these", "those"
        ]
        let blockedTrailingWords: Set<String> = ["each", "following", "above", "below", "other"]
        let blockedPhrases = [
            "for each", "of each", "schematic sketch", "characteristics for",
            "review questions", "chapter objectives", "learning objectives",
            "table of contents", "dedicated to"
        ]

        guard cleanedText.count >= 3, cleanedText.count <= 60 else { return false }
        guard words.count >= 1, words.count <= 7 else { return false }
        guard lettersRatio(in: cleanedText) > 0.55 else { return false }
        guard !looksLikeStructuralText(cleanedText), !looksLikeExercisePrompt(cleanedText) else { return false }
        guard !looksLikeAttributionText(cleanedText) else { return false }
        guard let firstWord = words.first, let lastWord = words.last else { return false }
        guard !blockedEdgeWords.contains(firstWord), !blockedEdgeWords.contains(lastWord) else { return false }
        guard !blockedTrailingWords.contains(lastWord) else { return false }
        guard !blockedPhrases.contains(where: { loweredText.contains($0) }) else { return false }

        if words.count == 1, blockedGenericConcepts.contains(lastWord) {
            return false
        }

        if words.count == 2,
           blockedGenericConcepts.contains(words[0]),
           blockedGenericConcepts.contains(lastWord) {
            return false
        }

        return true
    }

    private nonisolated static func extractedExamples(from text: String) -> [String] {
        let cleanedText = cleanupSpacing(
            in: text.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        )
        guard !cleanedText.isEmpty else { return [] }

        let commaSplit = cleanedText
            .components(separatedBy: ",")
            .map { cleanupSpacing(in: $0) }
            .filter { $0.count > 2 }

        if commaSplit.count >= 2 {
            return commaSplit
        }

        return cleanedText
            .components(separatedBy: " and ")
            .map { cleanupSpacing(in: $0) }
            .filter { $0.count > 2 }
    }

    private nonisolated static func conceptCandidates(in text: String, limit: Int) -> [String] {
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

            let token = cleanupSpacing(in: String(text[tokenRange]))
            guard token.count > 2 else { return true }

            switch tag {
            case .personalName, .placeName, .organizationName, .noun:
                if isUsefulKeyword(token) {
                    candidates[token, default: 0] += 3
                }
            default:
                break
            }

            return true
        }

        for token in tokens(in: text) {
            candidates[token.capitalized, default: 0] += 1
        }

        return uniqueCaseInsensitive(
            candidates
                .sorted { lhs, rhs in
                    if lhs.value == rhs.value {
                        return lhs.key.count > rhs.key.count
                    }
                    return lhs.value > rhs.value
                }
                .map(\.key),
            limit: limit
        )
    }

    private nonisolated static func uniqueCaseInsensitive(_ values: [String], limit: Int) -> [String] {
        var uniqueValues: [String] = []
        var seenValues = Set<String>()

        for value in values {
            let key = value.lowercased()
            guard !seenValues.contains(key) else { continue }

            seenValues.insert(key)
            uniqueValues.append(value)

            if uniqueValues.count == limit {
                break
            }
        }

        return uniqueValues
    }

    private nonisolated static func shortSummary(from text: String) -> String {
        let summary = compressedAnswer(from: text, maximumSentences: 1, maximumCharacters: 110)
        return cleanupSpacing(in: summary.replacingOccurrences(of: "\n", with: " "))
    }

    private nonisolated static func compressedAnswer(
        from text: String,
        maximumSentences: Int,
        maximumCharacters: Int
    ) -> String {
        let normalizedText = normalizeText(text)
        guard !normalizedText.isEmpty else { return "" }

        let sentences = splitSentences(normalizedText)
        guard !sentences.isEmpty else {
            return completedSentencePrefix(normalizedText, limit: maximumCharacters)
        }

        let selectedSentences = sentences
            .enumerated()
            .sorted { lhs, rhs in
                let lhsScore = sentencePriorityScore(for: lhs.element)
                let rhsScore = sentencePriorityScore(for: rhs.element)

                if lhsScore == rhsScore {
                    return lhs.offset < rhs.offset
                }

                return lhsScore > rhsScore
            }
            .prefix(maximumSentences)
            .sorted { $0.offset < $1.offset }
            .map(\.element)

        let summary = cleanupSpacing(
            in: selectedSentences
                .map { ensureSentenceEnding($0) }
                .joined(separator: " ")
        )

        return completedSentencePrefix(summary, limit: maximumCharacters)
    }

    private nonisolated static func completedSentencePrefix(_ text: String, limit: Int) -> String {
        let cleanedText = cleanupSpacing(in: text)
        guard cleanedText.count > limit else { return ensureSentenceEnding(cleanedText) }

        let prefixText = String(cleanedText.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)

        if let lastSentenceEnd = prefixText.lastIndex(where: { ".!?".contains($0) }) {
            return String(prefixText[...lastSentenceEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let lastSpace = prefixText.lastIndex(of: " ") {
            let shortenedText = String(prefixText[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
            return ensureSentenceEnding(shortenedText)
        }

        return ensureSentenceEnding(prefixText)
    }

    private nonisolated static func ensureSentenceEnding(_ text: String) -> String {
        let cleanedText = cleanupSpacing(in: text)
        guard !cleanedText.isEmpty else { return "" }

        if cleanedText.hasSuffix(".") || cleanedText.hasSuffix("!") || cleanedText.hasSuffix("?") {
            return cleanedText
        }

        return "\(cleanedText)."
    }

    private nonisolated static func sentencePriorityScore(for sentence: String) -> Int {
        let loweredSentence = sentence.lowercased()
        let conceptCount = Set(tokens(in: sentence)).count
        var score = conceptCount * 3

        let importantMarkers = [
            " because ", " refers to ", " means ", " causes ", " leads to ",
            " results in ", " includes ", " contains ", " first ", " next ", " finally "
        ]

        for marker in importantMarkers where loweredSentence.contains(marker) {
            score += 8
        }

        if sentence.count >= 35 && sentence.count <= 180 {
            score += 6
        }

        return score
    }

    private nonisolated static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = cleanupSpacing(
                in: text[range].trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            )

            if sentence.count > 15 {
                sentences.append(sentence)
            }

            return true
        }

        return sentences
    }

    private nonisolated static func tokens(in text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && isUsefulKeyword($0) }
    }

    private nonisolated static func normalizeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { cleanupSpacing(in: String($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private nonisolated static func cleanupSpacing(in text: String) -> String {
        text
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func isLikelyHeading(_ text: String) -> Bool {
        let trimmedText = cleanupSpacing(in: text)
        let words = trimmedText.split(separator: " ")

        return trimmedText.count <= 48
            && words.count <= 6
            && !trimmedText.contains("?")
            && !trimmedText.contains(":")
            && !looksLikeStructuralText(trimmedText)
    }

    private nonisolated static func looksDefinitionLike(_ text: String) -> Bool {
        let loweredText = text.lowercased()
        let markers = [" is ", " are ", " refers to ", " means ", " can be defined as "]
        return markers.contains(where: { loweredText.contains($0) })
    }

    private nonisolated static func containsProcessLanguage(_ text: String) -> Bool {
        let markers = [" first ", " next ", " then ", " finally ", " step ", " process "]
        return markers.contains(where: { text.contains($0) })
    }

    private nonisolated static func containsCauseLanguage(_ text: String) -> Bool {
        let markers = [" because ", " therefore ", " as a result ", " causes ", " leads to ", " important "]
        return markers.contains(where: { text.contains($0) })
    }

    private nonisolated static func looksLikeStructuralText(_ text: String) -> Bool {
        let loweredText = text.lowercased()
        let blockedTerms = [
            "table of contents", "contents", "references", "bibliography",
            "acknowledgements", "appendix", "learning outcomes",
            "student name", "student number", "module code", "university",
            "dedicated to", "review questions", "chapter objectives",
            "learning objectives", "discussion questions", "exercises",
            "all rights reserved"
        ]

        return blockedTerms.contains(where: { loweredText.contains($0) })
            || looksLikeAttributionText(text)
            || looksLikeExercisePrompt(text)
    }

    private nonisolated static func looksLikeAttributionText(_ text: String) -> Bool {
        let cleanedText = cleanupSpacing(in: text)
        let loweredText = cleanedText.lowercased()
        let creditMarkers = [
            "istockphoto", "alamy", "shutterstock", "getty", "courtesy of", "image credit",
            "photo credit", "photograph by", "photo by", "image by", "cover image",
            "cover design", "illustration by", "©", "all rights reserved",
            "in memory of", "father, lumberman, and friend"
        ]
        let shortStructuralPattern = #"^(chapter|part|section)\s+\d+\b"#
        let titleCaseNamePattern = #"^[A-Z][a-z]+(?:\s+[A-Z][a-z]+){2,3}$"#

        if creditMarkers.contains(where: { loweredText.contains($0) }) {
            return true
        }

        if cleanedText.range(of: shortStructuralPattern, options: .regularExpression) != nil,
           cleanedText.count <= 40 {
            return true
        }

        if cleanedText.range(of: titleCaseNamePattern, options: .regularExpression) != nil,
           cleanedText.count <= 50,
           looksLikeShortPersonCredit(cleanedText) {
            return true
        }

        return false
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

    private nonisolated static func looksLikeExercisePrompt(_ text: String) -> Bool {
        let cleanedText = cleanupSpacing(in: text)
        let loweredText = cleanedText.lowercased()
        let imperativePattern = #"^(\d+[\.\)]\s*)?(define|describe|name|list|state|give|calculate|draw|sketch|identify|write|discuss|show|find|determine)\b"#

        if loweredText.range(of: imperativePattern, options: .regularExpression) != nil {
            return true
        }

        if loweredText.hasPrefix("given the ")
            || loweredText.hasPrefix("using the ")
            || loweredText.hasPrefix("with the help of ") {
            return true
        }

        return false
    }

    private nonisolated static func lettersRatio(in text: String) -> Double {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return 0 }

        let letters = trimmedText.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let significantCharacters = trimmedText.unicodeScalars.filter { !$0.properties.isWhitespace }.count
        guard significantCharacters > 0 else { return 0 }

        return Double(letters) / Double(significantCharacters)
    }

    private nonisolated static func isUsefulKeyword(_ token: String) -> Bool {
        !stopWords.contains(token.lowercased())
    }

    private nonisolated static let stopWords: Set<String> = [
        "the", "and", "with", "from", "that", "this", "these", "those",
        "have", "has", "had", "into", "their", "there", "which", "what",
        "when", "where", "whose", "your", "about", "because", "through",
        "using", "used", "also", "than", "then", "them", "they", "will",
        "shall", "could", "would", "should", "very", "more", "most"
    ]
}
