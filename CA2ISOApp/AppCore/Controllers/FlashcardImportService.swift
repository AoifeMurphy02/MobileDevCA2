//
//  FlashcardImportService.swift
//  CA2ISOApp
//
//  Created by Meghana on 18/04/2026.
//

import Foundation
import NaturalLanguage
import PDFKit
import UIKit
import Vision

enum FlashcardImportError: LocalizedError {
    case unreadableFile
    case unsupportedFile
    case imageLoadFailed
    case textExtractionFailed
    case emptyContent

    nonisolated var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "The selected file could not be opened."
        case .unsupportedFile:
            return "That file type is not supported yet. Try a PDF, text file, or image."
        case .imageLoadFailed:
            return "The selected image could not be loaded."
        case .textExtractionFailed:
            return "I could not read text from that document."
        case .emptyContent:
            return "No readable study content was found, so no flashcards were created."
        }
    }
}

struct ImportedFlashcardContent: Sendable {
    let title: String
    let sourceType: String
    let text: String

    nonisolated init(title: String, sourceType: String, text: String) {
        self.title = title
        self.sourceType = sourceType
        self.text = text
    }
}

private struct RankedStudyChunk: Sendable {
    let orderIndex: Int
    let text: String
    let score: Int
    let chapterTitle: String?

    nonisolated init(orderIndex: Int, text: String, score: Int, chapterTitle: String? = nil) {
        self.orderIndex = orderIndex
        self.text = text
        self.score = score
        self.chapterTitle = chapterTitle
    }
}

enum FlashcardImportService {
    nonisolated static func importFile(from url: URL) async throws -> ImportedFlashcardContent {
        let _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        let ext = url.pathExtension.lowercased()

        if ext == "pdf" {
            return try importPDF(from: url)
        }

        if ["txt", "md", "rtf"].contains(ext) {
            return try importTextFile(from: url)
        }

        if let image = UIImage(contentsOfFile: url.path) {
            let text = try await extractText(from: [image])
            return ImportedFlashcardContent(
                title: url.deletingPathExtension().lastPathComponent,
                sourceType: "Imported Image",
                text: text
            )
        }

        throw FlashcardImportError.unsupportedFile
    }

    nonisolated static func importImageData(
        _ data: Data,
        title: String = "Photo Flashcards",
        sourceType: String = "Photo Library"
    ) async throws -> ImportedFlashcardContent {
        guard let image = UIImage(data: data) else {
            throw FlashcardImportError.imageLoadFailed
        }

        let text = try await extractText(from: [image])
        return ImportedFlashcardContent(title: title, sourceType: sourceType, text: text)
    }

    nonisolated static func importScannedDocument(from url: URL) async throws -> ImportedFlashcardContent {
        let content = try await importFile(from: url)
        return ImportedFlashcardContent(
            title: content.title,
            sourceType: "Scanned Document",
            text: content.text
        )
    }

    nonisolated static func buildSet(
        title: String,
        subject: String,
        topic: String,
        sourceType: String,
        text: String,
        availableSubjects: [String] = [],
        preferredSubject: String = ""
    ) throws -> FlashcardSet {
        let draftDeck = try buildLocalDraftDeck(
            title: title,
            subject: subject,
            topic: topic,
            sourceType: sourceType,
            text: text,
            availableSubjects: availableSubjects,
            preferredSubject: preferredSubject
        )

        return try buildSet(from: draftDeck)
    }

    nonisolated static func buildDraftDeck(
        title: String,
        subject: String,
        topic: String,
        sourceType: String,
        text: String,
        availableSubjects: [String] = [],
        preferredSubject: String = ""
    ) throws -> FlashcardDeckDraft {
        try buildLocalDraftDeck(
            title: title,
            subject: subject,
            topic: topic,
            sourceType: sourceType,
            text: text,
            availableSubjects: availableSubjects,
            preferredSubject: preferredSubject
        )
    }

    nonisolated static func buildDraftDeck(
        title: String,
        subject: String,
        topic: String,
        sourceType: String,
        text: String,
        availableSubjects: [String] = [],
        preferredSubject: String = ""
    ) async throws -> FlashcardDeckDraft {
        let localDraftDeck = try buildLocalDraftDeck(
            title: title,
            subject: subject,
            topic: topic,
            sourceType: sourceType,
            text: text,
            availableSubjects: availableSubjects,
            preferredSubject: preferredSubject
        )

        guard let provider = FlashcardAISettingsStore.configuredProvider() else {
            return localDraftDeck
        }

        do {
            let cloudSuggestion = try await generateCloudSuggestion(
                using: provider,
                from: localDraftDeck
            )

            return mergeCloudSuggestion(
                cloudSuggestion,
                into: localDraftDeck,
                providerKind: provider.providerKind,
                providerModelID: provider.providerModelID
            )
        } catch {
            print("Advanced AI flashcard fallback: \(error.localizedDescription)")
            return localDraftDeck
        }
    }

    private nonisolated static func buildLocalDraftDeck(
        title: String,
        subject: String,
        topic: String,
        sourceType: String,
        text: String,
        availableSubjects: [String] = [],
        preferredSubject: String = ""
    ) throws -> FlashcardDeckDraft {
        let normalizedOriginalText = normalizeText(text)
        guard !normalizedOriginalText.isEmpty else {
            throw FlashcardImportError.emptyContent
        }

        let prioritizedText = curatedStudyText(from: normalizedOriginalText)
        var workingText = prioritizedText.isEmpty ? normalizedOriginalText : prioritizedText
        var generatedDrafts = makeDrafts(from: workingText)

        if generatedDrafts.count < 8 {
            let expandedStudyText = curatedStudyText(
                from: normalizedOriginalText,
                maximumLineCount: 360,
                minimumBlockScore: 4,
                maximumCharacters: 18_000
            )

            if !expandedStudyText.isEmpty, normalizeText(expandedStudyText) != normalizeText(workingText) {
                generatedDrafts.append(contentsOf: makeDrafts(from: expandedStudyText))
                workingText = normalizeText([workingText, expandedStudyText].joined(separator: "\n\n"))
            }
        }

        let drafts = annotatedDrafts(
            sanitizedDrafts(
                FlashcardAIEnhancer.finalizeDrafts(
                    generatedDrafts,
                    sourceText: workingText
                ),
                sourceText: workingText
            ),
            sourceText: workingText
        )
        guard !drafts.isEmpty else {
            throw FlashcardImportError.emptyContent
        }

        let metadataSuggestion = FlashcardAIEnhancer.suggestMetadata(
            from: workingText,
            fallbackTitle: title,
            availableSubjects: availableSubjects,
            preferredSubject: preferredSubject.isEmpty ? subject : preferredSubject,
            fallbackTopic: topic
        )

        return FlashcardDeckDraft(
            title: metadataSuggestion.title,
            sourceType: sourceType,
            subject: metadataSuggestion.subject,
            topic: metadataSuggestion.topic,
            rawText: workingText,
            aiGenerationMode: "local",
            aiModelID: "",
            cards: drafts
        )
    }

    nonisolated static func buildSet(from draftDeck: FlashcardDeckDraft) throws -> FlashcardSet {
        let sanitizedCards = sanitizedDrafts(draftDeck.cards, sourceText: draftDeck.rawText)
        guard !sanitizedCards.isEmpty else {
            throw FlashcardImportError.emptyContent
        }

        let resolvedTitle = draftDeck.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Smart Flashcards"
            : draftDeck.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSourceType = draftDeck.sourceType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Smart Generation"
            : draftDeck.sourceType.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSubject = draftDeck.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTopic = draftDeck.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedRawText = normalizeText(
            draftDeck.rawText.isEmpty
                ? sanitizedCards.map { "\($0.question)\n\($0.answer)" }.joined(separator: "\n")
                : draftDeck.rawText
        )
        let resolvedAIGenerationMode = draftDeck.aiGenerationMode.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAIModelID = draftDeck.aiModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let drafts = annotatedDrafts(sanitizedCards, sourceText: resolvedRawText)

        let flashcardSet = FlashcardSet(
            title: resolvedTitle,
            sourceType: resolvedSourceType,
            subject: resolvedSubject,
            topic: resolvedTopic,
            rawText: resolvedRawText,
            aiGenerationMode: resolvedAIGenerationMode,
            aiModelID: resolvedAIModelID
        )

        flashcardSet.cards = drafts.enumerated().map { index, draft in
            Flashcard(
                question: draft.question,
                answer: draft.answer,
                confidenceRawValue: draft.confidence.rawValue,
                evidenceExcerpt: draft.evidenceExcerpt,
                orderIndex: index,
                parentSet: flashcardSet
            )
        }

        return flashcardSet
    }

    private nonisolated static func mergeCloudSuggestion(
        _ suggestion: FlashcardCloudDeckSuggestion,
        into localDraftDeck: FlashcardDeckDraft,
        providerKind: String,
        providerModelID: String
    ) -> FlashcardDeckDraft {
        let cloudDrafts = sanitizedCloudDrafts(suggestion.cards, sourceText: localDraftDeck.rawText)
        guard cloudDrafts.count >= 6 else {
            return localDraftDeck
        }

        let supplementalLocalDrafts: [FlashcardDraft]
        if cloudDrafts.count >= 8 {
            supplementalLocalDrafts = []
        } else {
            let existingKeys = Set(cloudDrafts.map(draftIdentityKey))
            supplementalLocalDrafts = localDraftDeck.cards.filter { draft in
                !existingKeys.contains(draftIdentityKey(draft))
            }
        }

        let preferredDrafts = cloudDrafts + Array(
            supplementalLocalDrafts.prefix(max(10 - cloudDrafts.count, 0))
        )
        let mergedDrafts = annotatedDrafts(
            sanitizedDrafts(
                FlashcardAIEnhancer.finalizeDrafts(
                    preferredDrafts,
                    sourceText: localDraftDeck.rawText
                ),
                sourceText: localDraftDeck.rawText
            ),
            sourceText: localDraftDeck.rawText
        )

        guard !mergedDrafts.isEmpty else {
            return localDraftDeck
        }

        return FlashcardDeckDraft(
            title: preferredMetadataValue(suggestion.title, fallback: localDraftDeck.title),
            sourceType: localDraftDeck.sourceType,
            subject: preferredMetadataValue(suggestion.subject, fallback: localDraftDeck.subject),
            topic: preferredMetadataValue(suggestion.topic, fallback: localDraftDeck.topic),
            rawText: localDraftDeck.rawText,
            aiGenerationMode: providerKind,
            aiModelID: providerModelID,
            cards: mergedDrafts
        )
    }

    private nonisolated static func generateCloudSuggestion(
        using provider: any FlashcardLLMProvider,
        from localDraftDeck: FlashcardDeckDraft
    ) async throws -> FlashcardCloudDeckSuggestion {
        let focusedRequests = focusedCloudGenerationRequests(
            from: localDraftDeck,
            providerKind: provider.providerKind
        )

        if focusedRequests.count >= 2 {
            var partialSuggestions: [FlashcardCloudDeckSuggestion] = []

            for request in focusedRequests {
                do {
                    let suggestion = try await provider.generateDeckSuggestion(from: request)
                    let sanitizedCount = sanitizedCloudDrafts(
                        suggestion.cards,
                        sourceText: localDraftDeck.rawText
                    ).count

                    if sanitizedCount > 0 {
                        partialSuggestions.append(suggestion)
                    }
                } catch {
                    print("Focused AI section skipped: \(error.localizedDescription)")
                }
            }

            let combinedSuggestion = combinedCloudSuggestion(
                from: partialSuggestions,
                fallbackDeck: localDraftDeck
            )
            let combinedCardCount = sanitizedCloudDrafts(
                combinedSuggestion.cards,
                sourceText: localDraftDeck.rawText
            ).count

            if combinedCardCount >= 6 {
                return combinedSuggestion
            }
        }

        return try await provider.generateDeckSuggestion(
            from: wholeDocumentCloudRequest(
                from: localDraftDeck,
                providerKind: provider.providerKind
            )
        )
    }

    private nonisolated static func focusedCloudGenerationRequests(
        from localDraftDeck: FlashcardDeckDraft,
        providerKind: String
    ) -> [FlashcardCloudGenerationRequest] {
        let sourceAnalysis = FlashcardSourceAnalyzer.analyze(localDraftDeck.rawText)
        let selectedSections = selectedCloudSections(
            from: sourceAnalysis.sections,
            sourceText: localDraftDeck.rawText,
            providerKind: providerKind
        )
        guard selectedSections.count >= 2 else { return [] }

        let documentContext = cloudDocumentContext(
            from: sourceAnalysis,
            selectedSections: selectedSections
        )
        let totalCardBudget = providerKind == "apple-intelligence"
            ? min(max(localDraftDeck.cards.count, 8), 10)
            : min(max(localDraftDeck.cards.count, 10), 14)
        var remainingCards = totalCardBudget
        var remainingSections = selectedSections.count
        var requests: [FlashcardCloudGenerationRequest] = []

        for section in selectedSections {
            let cardsForSection = max(
                2,
                min(
                    providerKind == "apple-intelligence" ? 3 : 4,
                    Int(ceil(Double(remainingCards) / Double(max(remainingSections, 1))))
                )
            )

            requests.append(
                FlashcardCloudGenerationRequest(
                    title: localDraftDeck.title,
                    subject: localDraftDeck.subject,
                    topic: localDraftDeck.topic,
                    sourceType: localDraftDeck.sourceType,
                    text: normalizeText("\(section.title)\n\(section.body)"),
                    focusTitle: section.title,
                    requestedCardCount: cardsForSection,
                    documentContext: documentContext
                )
            )

            remainingCards = max(remainingCards - cardsForSection, 0)
            remainingSections -= 1
        }

        return requests
    }

    private nonisolated static func wholeDocumentCloudRequest(
        from localDraftDeck: FlashcardDeckDraft,
        providerKind: String = ""
    ) -> FlashcardCloudGenerationRequest {
        let sourceAnalysis = FlashcardSourceAnalyzer.analyze(localDraftDeck.rawText)

        return FlashcardCloudGenerationRequest(
            title: localDraftDeck.title,
            subject: localDraftDeck.subject,
            topic: localDraftDeck.topic,
            sourceType: localDraftDeck.sourceType,
            text: localDraftDeck.rawText,
            requestedCardCount: providerKind == "apple-intelligence"
                ? min(max(localDraftDeck.cards.count, 8), 10)
                : min(max(localDraftDeck.cards.count, 10), 14),
            documentContext: cloudDocumentContext(
                from: sourceAnalysis,
                selectedSections: selectedCloudSections(
                    from: sourceAnalysis.sections,
                    sourceText: localDraftDeck.rawText,
                    providerKind: providerKind
                )
            )
        )
    }

    private nonisolated static func combinedCloudSuggestion(
        from suggestions: [FlashcardCloudDeckSuggestion],
        fallbackDeck: FlashcardDeckDraft
    ) -> FlashcardCloudDeckSuggestion {
        var resolvedTitle = fallbackDeck.title
        var resolvedSubject = fallbackDeck.subject
        var resolvedTopic = fallbackDeck.topic

        for suggestion in suggestions {
            resolvedTitle = preferredMetadataValue(suggestion.title, fallback: resolvedTitle)
            resolvedSubject = preferredMetadataValue(suggestion.subject, fallback: resolvedSubject)
            resolvedTopic = preferredMetadataValue(suggestion.topic, fallback: resolvedTopic)
        }

        return FlashcardCloudDeckSuggestion(
            title: resolvedTitle,
            subject: resolvedSubject,
            topic: resolvedTopic,
            cards: suggestions
                .flatMap { suggestion in
                    suggestion.cards
                }
                .prefix(18)
                .map { $0 }
        )
    }

    private nonisolated static func selectedCloudSections(
        from sections: [FlashcardSourceSection],
        sourceText: String,
        providerKind: String
    ) -> [FlashcardSourceSection] {
        let eligibleSections = sections.enumerated().compactMap { element -> (index: Int, section: FlashcardSourceSection)? in
            let section = element.element
            guard section.body.count >= 120 else { return nil }
            guard studyScore(for: section.body) >= 10 else { return nil }
            guard isSpecificStudyConcept(section.title)
                || section.concepts.contains(where: isSpecificStudyConcept) else {
                return nil
            }

            return (index: element.offset, section: section)
        }

        let maximumCount: Int
        switch sourceText.count {
        case 18_001...:
            maximumCount = providerKind == "apple-intelligence" ? 3 : 5
        case 10_001...:
            maximumCount = providerKind == "apple-intelligence" ? 3 : 4
        default:
            maximumCount = providerKind == "apple-intelligence" ? 2 : 3
        }

        guard eligibleSections.count > maximumCount else {
            return eligibleSections.map { $0.section }
        }

        var selected: [(index: Int, section: FlashcardSourceSection)] = []
        let bucketCount = min(maximumCount, 6)

        for bucketIndex in 0..<bucketCount {
            let startIndex = bucketIndex * eligibleSections.count / bucketCount
            let endIndex = (bucketIndex + 1) * eligibleSections.count / bucketCount
            let bucket = Array(eligibleSections[startIndex..<endIndex])

            guard let bestSection = bucket.max(by: {
                cloudSectionScore($0.section) < cloudSectionScore($1.section)
            }) else {
                continue
            }

            selected.append(bestSection)
        }

        let selectedIndexes = Set(selected.map { $0.index })
        let remainingSections = eligibleSections
            .filter { !selectedIndexes.contains($0.index) }
            .sorted { lhs, rhs in
                cloudSectionScore(lhs.section) > cloudSectionScore(rhs.section)
            }

        for section in remainingSections {
            guard selected.count < maximumCount else { break }
            selected.append(section)
        }

        return selected
            .sorted { $0.index < $1.index }
            .map { $0.section }
    }

    private nonisolated static func cloudSectionScore(_ section: FlashcardSourceSection) -> Int {
        let conceptScore = min(section.concepts.filter(isSpecificStudyConcept).count * 6, 18)
        let titleScore = isSpecificStudyConcept(section.title) ? 10 : 0
        let lengthScore = min(section.body.count / 80, 8)

        return studyScore(for: section.body) + conceptScore + titleScore + lengthScore
    }

    private nonisolated static func cloudDocumentContext(
        from sourceAnalysis: FlashcardSourceAnalysis,
        selectedSections: [FlashcardSourceSection]
    ) -> String {
        let dominantConcepts = sourceAnalysis.dominantConcepts.prefix(8).joined(separator: ", ")
        let sectionMap = selectedSections
            .map { $0.title }
            .joined(separator: " | ")

        return """
        Main concepts: \(dominantConcepts.isEmpty ? "None extracted." : dominantConcepts)
        Study map: \(sectionMap.isEmpty ? "No section map detected." : sectionMap)
        Use the focus section for the actual card content. Use this overview only to keep the topic and wording consistent.
        """
    }

    private nonisolated static func importPDF(from url: URL) throws -> ImportedFlashcardContent {
        guard let document = PDFDocument(url: url) else {
            throw FlashcardImportError.unreadableFile
        }

        let rawDocumentText = (0..<document.pageCount)
            .compactMap { (pageIndex: Int) -> String? in
                document.page(at: pageIndex)?.string
            }
            .joined(separator: "\n\n")

        var scoredPages: [RankedStudyChunk] = []
        var currentChapterTitle: String?

        for pageIndex in 0..<document.pageCount {
            guard let rawPageText = document.page(at: pageIndex)?.string else {
                continue
            }

            if let detectedChapterTitle = detectedChapterTitle(in: rawPageText) {
                currentChapterTitle = detectedChapterTitle
            }

            let curatedPageText = curatedStudyText(
                from: rawPageText,
                maximumLineCount: 70,
                minimumBlockScore: 10,
                maximumCharacters: 1_800
            )
            guard !curatedPageText.isEmpty else { continue }

            let score = studyScore(for: curatedPageText)
            guard score > 0 else { continue }

            scoredPages.append(
                RankedStudyChunk(
                    orderIndex: pageIndex,
                    text: curatedPageText,
                    score: score,
                    chapterTitle: currentChapterTitle
                )
            )
        }

        let resolvedText = wholeDocumentStudyText(
            from: scoredPages,
            fallbackText: rawDocumentText,
            maximumCharacters: 24_000
        )
        guard !resolvedText.isEmpty else {
            throw FlashcardImportError.textExtractionFailed
        }

        return ImportedFlashcardContent(
            title: url.deletingPathExtension().lastPathComponent,
            sourceType: "PDF File",
            text: resolvedText
        )
    }

    private nonisolated static func importTextFile(from url: URL) throws -> ImportedFlashcardContent {
        guard let data = try? Data(contentsOf: url) else {
            throw FlashcardImportError.unreadableFile
        }

        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .unicode)
            ?? String(data: data, encoding: .ascii)

        guard let text else {
            throw FlashcardImportError.textExtractionFailed
        }

        let curatedText = curatedStudyText(
            from: text,
            maximumLineCount: 520,
            minimumBlockScore: 6,
            maximumCharacters: 22_000
        )
        guard !curatedText.isEmpty else {
            throw FlashcardImportError.textExtractionFailed
        }

        return ImportedFlashcardContent(
            title: url.deletingPathExtension().lastPathComponent,
            sourceType: "Text File",
            text: curatedText
        )
    }

    private nonisolated static func extractText(from images: [UIImage]) async throws -> String {
        var snippets: [String] = []

        for image in images {
            let lines = try await recognizeText(in: image)
            if !lines.isEmpty {
                snippets.append(lines.joined(separator: "\n"))
            }
        }

        let cleanedText = curatedStudyText(from: snippets.joined(separator: "\n"))
        guard !cleanedText.isEmpty else {
            throw FlashcardImportError.textExtractionFailed
        }

        return cleanedText
    }

    private nonisolated static func recognizeText(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else {
            throw FlashcardImportError.imageLoadFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { (observation: VNRecognizedTextObservation) -> String? in
                    observation.topCandidates(1).first?.string
                }
                continuation.resume(returning: lines)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private nonisolated static func makeDrafts(from text: String) -> [FlashcardDraft] {
        let normalizedLines = studyLines(from: text)
        guard !normalizedLines.isEmpty else { return [] }

        let normalizedStudyText = normalizeText(normalizedLines.joined(separator: "\n"))
        let sourceAnalysis = FlashcardSourceAnalyzer.analyze(normalizedStudyText)

        var drafts: [FlashcardDraft] = []
        var seenPairs = Set<String>()

        for draft in extractDefinitionPairs(from: normalizedLines) {
            appendDraft(draft, to: &drafts, seenPairs: &seenPairs)
        }

        for draft in extractTabularDefinitionPairs(from: normalizedLines) {
            appendDraft(draft, to: &drafts, seenPairs: &seenPairs)
        }

        for draft in extractQuestionAnswerPairs(from: normalizedLines) {
            appendDraft(draft, to: &drafts, seenPairs: &seenPairs)
        }

        for draft in extractBulletGroupCards(from: normalizedLines) {
            appendDraft(draft, to: &drafts, seenPairs: &seenPairs)
        }

        for draft in extractProcessCards(from: normalizedLines) {
            appendDraft(draft, to: &drafts, seenPairs: &seenPairs)
        }

        for draft in sourceAnalysis.suggestedDrafts {
            appendDraft(draft, to: &drafts, seenPairs: &seenPairs)
        }

        for draft in extractSentenceBasedCards(from: normalizedStudyText) {
            appendDraft(draft, to: &drafts, seenPairs: &seenPairs)
        }

        if drafts.count < 6 {
            for draft in fallbackCards(from: normalizedLines) {
                appendDraft(draft, to: &drafts, seenPairs: &seenPairs)
            }
        }

        return Array(drafts.prefix(42))
    }

    private nonisolated static func sanitizedDrafts(
        _ drafts: [FlashcardDraft],
        sourceText: String = ""
    ) -> [FlashcardDraft] {
        var sanitized: [FlashcardDraft] = []
        var seenPairs = Set<String>()

        for draft in drafts {
            let polishedDraft = polishedDraft(draft, sourceText: sourceText)
            let normalizedQuestion = cleanupSpacing(in: polishedDraft.question)
            let normalizedAnswer = cleanupSpacing(in: polishedDraft.answer)

            guard normalizedQuestion.count > 6, normalizedAnswer.count > 6 else { continue }
            guard isStudyQuestion(normalizedQuestion), isStudyAnswer(normalizedAnswer) else { continue }

            let key = "\(normalizedQuestion.lowercased())|\(normalizedAnswer.lowercased())"
            guard !seenPairs.contains(key) else { continue }

            seenPairs.insert(key)
            sanitized.append(
                FlashcardDraft(
                    id: polishedDraft.id,
                    question: normalizedQuestion,
                    answer: normalizedAnswer,
                    style: polishedDraft.style,
                    confidence: polishedDraft.confidence,
                    evidenceExcerpt: cleanupInlineText(polishedDraft.evidenceExcerpt)
                )
            )
        }

        return sanitized
    }

    private nonisolated static func appendDraft(
        _ draft: FlashcardDraft,
        to drafts: inout [FlashcardDraft],
        seenPairs: inout Set<String>
    ) {
        let polishedDraft = polishedDraft(draft, sourceText: "")
        let normalizedQuestion = cleanupSpacing(in: polishedDraft.question)
        let normalizedAnswer = cleanupSpacing(in: polishedDraft.answer)

        guard normalizedQuestion.count > 6, normalizedAnswer.count > 6 else { return }
        guard isStudyQuestion(normalizedQuestion), isStudyAnswer(normalizedAnswer) else { return }

        let key = "\(normalizedQuestion.lowercased())|\(normalizedAnswer.lowercased())"
        guard !seenPairs.contains(key) else { return }

        seenPairs.insert(key)
        drafts.append(
            FlashcardDraft(
                id: polishedDraft.id,
                question: normalizedQuestion,
                answer: normalizedAnswer,
                style: polishedDraft.style,
                confidence: polishedDraft.confidence,
                evidenceExcerpt: cleanupInlineText(polishedDraft.evidenceExcerpt)
            )
        )
    }

    private nonisolated static func sanitizedCloudDrafts(
        _ suggestions: [FlashcardCloudCardSuggestion],
        sourceText: String
    ) -> [FlashcardDraft] {
        sanitizedDrafts(
            suggestions.map { suggestion in
                FlashcardDraft(
                    question: cleanupInlineText(suggestion.question),
                    answer: cleanupInlineText(suggestion.answer),
                    style: suggestion.style,
                    confidence: suggestion.confidence,
                    evidenceExcerpt: validatedEvidenceExcerpt(
                        suggestion.evidenceExcerpt,
                        question: suggestion.question,
                        answer: suggestion.answer,
                        sourceText: sourceText
                    )
                )
            },
            sourceText: sourceText
        )
    }

    private nonisolated static func annotatedDrafts(
        _ drafts: [FlashcardDraft],
        sourceText: String
    ) -> [FlashcardDraft] {
        drafts.map { draft in
            let polishedDraft = polishedDraft(draft, sourceText: sourceText)
            let resolvedEvidence = validatedEvidenceExcerpt(
                polishedDraft.evidenceExcerpt,
                question: polishedDraft.question,
                answer: polishedDraft.answer,
                sourceText: sourceText
            )
            let suggestedConfidence = FlashcardAIEnhancer.confidence(
                for: FlashcardDraft(
                    id: polishedDraft.id,
                    question: polishedDraft.question,
                    answer: polishedDraft.answer,
                    style: polishedDraft.style,
                    confidence: polishedDraft.confidence,
                    evidenceExcerpt: resolvedEvidence
                ),
                sourceText: sourceText
            )
            let resolvedConfidence = polishedDraft.confidence.rank >= suggestedConfidence.rank
                ? polishedDraft.confidence
                : suggestedConfidence

            return FlashcardDraft(
                id: polishedDraft.id,
                question: polishedDraft.question,
                answer: polishedDraft.answer,
                style: polishedDraft.style,
                confidence: resolvedConfidence,
                evidenceExcerpt: resolvedEvidence
            )
        }
    }

    private nonisolated static func preferredMetadataValue(_ candidate: String, fallback: String) -> String {
        let cleanedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedCandidate.isEmpty {
            return cleanedCandidate
        }

        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func draftIdentityKey(_ draft: FlashcardDraft) -> String {
        "\(cleanupInlineText(draft.question).lowercased())|\(cleanupInlineText(draft.answer).lowercased())"
    }

    private nonisolated static func validatedEvidenceExcerpt(
        _ excerpt: String,
        question: String,
        answer: String,
        sourceText: String
    ) -> String {
        let cleanedExcerpt = cleanupInlineText(excerpt)
        if !cleanedExcerpt.isEmpty, containsNormalizedSnippet(cleanedExcerpt, in: sourceText) {
            return cleanedExcerpt
        }

        return FlashcardAIEnhancer.bestEvidenceExcerpt(
            for: FlashcardDraft(
                question: question,
                answer: answer,
                evidenceExcerpt: cleanedExcerpt
            ),
            sourceText: sourceText
        )
    }

    private nonisolated static func extractDefinitionPairs(from lines: [String]) -> [FlashcardDraft] {
        var drafts: [FlashcardDraft] = []

        for line in lines {
            if let draft = draftFromDelimitedLine(line) {
                drafts.append(draft)
            }
        }

        return drafts
    }

    private nonisolated static func extractTabularDefinitionPairs(from lines: [String]) -> [FlashcardDraft] {
        var drafts: [FlashcardDraft] = []

        for line in lines {
            let parts = line
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }

            guard parts.count >= 4 else { continue }
            guard let separatorRange = line.range(of: #"\s{2,}"#, options: .regularExpression) else { continue }

            let term = String(line[..<separatorRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let definition = String(line[separatorRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard isReasonablePrompt(term), definition.count > 10 else { continue }

            drafts.append(
                FlashcardDraft(
                    question: "What is \(term)?",
                    answer: compressedAnswer(from: definition),
                    style: .definition
                )
            )
        }

        return drafts
    }

    private nonisolated static func extractBulletGroupCards(from lines: [String]) -> [FlashcardDraft] {
        guard lines.count > 2 else { return [] }

        var drafts: [FlashcardDraft] = []
        var index = 0

        while index < lines.count {
            let heading = lines[index]
            guard isLikelyHeading(heading) else {
                index += 1
                continue
            }

            var bulletItems: [String] = []
            var lookAheadIndex = index + 1

            while lookAheadIndex < lines.count {
                let line = lines[lookAheadIndex]

                if isLikelyHeading(line) && !isBulletLine(line) {
                    break
                }

                if let cleanedBullet = cleanedBulletItem(from: line), cleanedBullet.count > 5 {
                    bulletItems.append(cleanedBullet)
                } else if !bulletItems.isEmpty {
                    break
                }

                lookAheadIndex += 1
            }

            if bulletItems.count >= 2 {
                drafts.append(
                    FlashcardDraft(
                        question: "What are the key points about \(heading)?",
                        answer: bulletItems
                            .prefix(5)
                            .map { "• \($0)" }
                            .joined(separator: "\n"),
                        style: .summary
                    )
                )
            }

            index = max(index + 1, lookAheadIndex)
        }

        return drafts
    }

    private nonisolated static func extractHeadingContextCards(from lines: [String]) -> [FlashcardDraft] {
        guard lines.count > 1 else { return [] }
        var drafts: [FlashcardDraft] = []

        for index in 0..<(lines.count - 1) {
            let heading = lines[index]
            guard isLikelyHeading(heading) else { continue }

            var details: [String] = []
            var lookAheadIndex = index + 1

            while lookAheadIndex < lines.count {
                let line = lines[lookAheadIndex]

                if isLikelyHeading(line) && !details.isEmpty {
                    break
                }

                if isStudyLine(line) && !isLikelyHeading(line) {
                    details.append(line)
                }

                let combinedCount = details.joined(separator: " ").count
                if details.count == 4 || combinedCount > 380 {
                    break
                }

                lookAheadIndex += 1
            }

            let detail = compressedAnswer(from: details.joined(separator: " "))
            guard detail.count > 30 else { continue }

            drafts.append(
                FlashcardDraft(
                    question: "Explain \(heading)",
                    answer: detail,
                    style: .explanation
                )
            )
        }

        return drafts
    }

    private nonisolated static func extractParagraphSummaryCards(from text: String) -> [FlashcardDraft] {
        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { normalizeText($0) }
            .filter { isStudyParagraph($0) }

        var drafts: [FlashcardDraft] = []

        for paragraph in paragraphs.prefix(12) {
            guard let heading = bestKeyword(in: paragraph, allowVerbs: false) else {
                continue
            }

            let answer = compressedAnswer(from: paragraph, maximumSentences: 3, maximumCharacters: 240)
            guard answer.count > 30 else { continue }

            drafts.append(
                FlashcardDraft(
                    question: "What should you understand about \(heading)?",
                    answer: answer,
                    style: .summary
                )
            )
        }

        return drafts
    }

    private nonisolated static func extractProcessCards(from lines: [String]) -> [FlashcardDraft] {
        guard lines.count > 2 else { return [] }

        var drafts: [FlashcardDraft] = []
        var index = 0

        while index < lines.count {
            let heading = lines[index]
            guard isLikelyHeading(heading) else {
                index += 1
                continue
            }

            var numberedSteps: [String] = []
            var lookAheadIndex = index + 1

            while lookAheadIndex < lines.count {
                let line = lines[lookAheadIndex]

                if isLikelyHeading(line) && !isNumberedStep(line) {
                    break
                }

                if let cleanedStep = cleanedNumberedStep(from: line), cleanedStep.count > 5 {
                    numberedSteps.append(cleanedStep)
                } else if !numberedSteps.isEmpty {
                    break
                }

                lookAheadIndex += 1
            }

            if numberedSteps.count >= 2 {
                drafts.append(
                    FlashcardDraft(
                        question: "How does \(heading) work?",
                        answer: numberedSteps
                            .prefix(5)
                            .enumerated()
                            .map { offset, step in
                                "\(offset + 1). \(step)"
                            }
                            .joined(separator: "\n"),
                        style: .how
                    )
                )
            }

            index = max(index + 1, lookAheadIndex)
        }

        return drafts
    }

    private nonisolated static func draftFromDelimitedLine(_ line: String) -> FlashcardDraft? {
        let delimiters = [":", " - ", " – ", " — ", " = "]

        for delimiter in delimiters {
            guard let range = line.range(of: delimiter) else { continue }

            let term = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let definition = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard isReasonablePrompt(term), definition.count > 8 else { continue }

            return FlashcardDraft(
                question: term.hasSuffix("?") ? term : "What is \(term)?",
                answer: compressedAnswer(from: definition),
                style: term.hasSuffix("?") ? inferredStyle(from: term) : .definition
            )
        }

        return nil
    }

    private nonisolated static func extractQuestionAnswerPairs(from lines: [String]) -> [FlashcardDraft] {
        guard lines.count > 1 else { return [] }
        var drafts: [FlashcardDraft] = []
        var index = 0

        while index < lines.count - 1 {
            let questionLine = lines[index]
            guard questionLine.hasSuffix("?") else {
                index += 1
                continue
            }

            var answerLines: [String] = []
            var lookAheadIndex = index + 1

            while lookAheadIndex < lines.count {
                let line = lines[lookAheadIndex]

                if line.hasSuffix("?") && !answerLines.isEmpty {
                    break
                }

                if isLikelyHeading(line) && !answerLines.isEmpty {
                    break
                }

                if isStudyLine(line) {
                    answerLines.append(line)
                }

                if answerLines.count == 3 || answerLines.joined(separator: " ").count > 260 {
                    break
                }

                lookAheadIndex += 1
            }

            let answer = compressedAnswer(from: answerLines.joined(separator: " "))
            if answer.count > 6 {
                drafts.append(
                    FlashcardDraft(
                        question: questionLine,
                        answer: answer,
                        style: inferredStyle(from: questionLine)
                    )
                )
            }

            index = max(index + 1, lookAheadIndex)
        }

        return drafts
    }

    private nonisolated static func extractSentenceBasedCards(from text: String) -> [FlashcardDraft] {
        let sentences = Array(
            splitSentences(text)
                .filter(isCandidateStudySentence)
                .prefix(32)
        )
        var drafts: [FlashcardDraft] = []

        for sentence in sentences {
            if let draft = makeDefinitionSentenceCard(from: sentence) {
                drafts.append(draft)
                continue
            }

            if let draft = makePurposeCard(from: sentence) {
                drafts.append(draft)
                continue
            }
        }

        return drafts
    }

    private nonisolated static func makeDefinitionSentenceCard(from sentence: String) -> FlashcardDraft? {
        let patterns = [
            #"^(.{2,55}?)\s+is\s+(.{8,240})$"#,
            #"^(.{2,55}?)\s+are\s+(.{8,240})$"#,
            #"^(.{2,55}?)\s+refers to\s+(.{8,240})$"#,
            #"^(.{2,55}?)\s+means\s+(.{8,240})$"#,
            #"^(.{2,55}?)\s+can be defined as\s+(.{8,240})$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let range = NSRange(sentence.startIndex..<sentence.endIndex, in: sentence)
            guard let match = regex.firstMatch(in: sentence, options: [], range: range),
                  match.numberOfRanges == 3,
                  let termRange = Range(match.range(at: 1), in: sentence),
                  let definitionRange = Range(match.range(at: 2), in: sentence) else {
                continue
            }

            let term = sentence[termRange].trimmingCharacters(in: .whitespacesAndNewlines)
            let definition = sentence[definitionRange].trimmingCharacters(in: .whitespacesAndNewlines)

            guard isReasonablePrompt(term), isSpecificStudyConcept(term) else { continue }

            return FlashcardDraft(
                question: "What is \(term)?",
                answer: compressedAnswer(from: definition.trimmingCharacters(in: CharacterSet(charactersIn: ". "))),
                style: .definition
            )
        }

        return nil
    }

    private nonisolated static func makePurposeCard(from sentence: String) -> FlashcardDraft? {
        let patterns = [
            #"^(.{2,60}?)\s+is used to\s+(.{8,220})$"#,
            #"^(.{2,60}?)\s+are used to\s+(.{8,220})$"#,
            #"^(.{2,60}?)\s+helps\s+(.{8,220})$"#,
            #"^(.{2,60}?)\s+allows\s+(.{8,220})$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let range = NSRange(sentence.startIndex..<sentence.endIndex, in: sentence)
            guard let match = regex.firstMatch(in: sentence, options: [], range: range),
                  match.numberOfRanges == 3,
                  let subjectRange = Range(match.range(at: 1), in: sentence),
                  let remainderRange = Range(match.range(at: 2), in: sentence) else {
                continue
            }

            let subject = sentence[subjectRange].trimmingCharacters(in: .whitespacesAndNewlines)
            let remainder = sentence[remainderRange].trimmingCharacters(in: .whitespacesAndNewlines)

            guard isReasonablePrompt(subject), isSpecificStudyConcept(subject), remainder.count > 8 else { continue }

            return FlashcardDraft(
                question: "What is \(subject) used for?",
                answer: compressedAnswer(from: remainder.trimmingCharacters(in: CharacterSet(charactersIn: ". "))),
                style: .how
            )
        }

        return nil
    }

    private nonisolated static func fallbackCards(from lines: [String]) -> [FlashcardDraft] {
        lines
            .filter { isStudyLine($0) }
            .sorted { studyScore(for: $0) > studyScore(for: $1) }
            .prefix(16)
            .compactMap { line in
                if let definitionDraft = makeDefinitionSentenceCard(from: line) {
                    return definitionDraft
                }

                if let purposeDraft = makePurposeCard(from: line) {
                    return purposeDraft
                }

                return nil
            }
    }

    private nonisolated static func polishedDraft(
        _ draft: FlashcardDraft,
        sourceText: String
    ) -> FlashcardDraft {
        let polishedAnswer = polishedAnswerText(draft.answer)
        let polishedQuestion = polishedQuestionText(
            draft.question,
            answer: polishedAnswer,
            style: draft.style,
            sourceText: sourceText
        )
        let inferredQuestionStyle = inferredStyle(from: polishedQuestion)

        return FlashcardDraft(
            id: draft.id,
            question: polishedQuestion,
            answer: polishedAnswer,
            style: inferredQuestionStyle == .summary ? draft.style : inferredQuestionStyle,
            confidence: draft.confidence,
            evidenceExcerpt: cleanupInlineText(draft.evidenceExcerpt)
        )
    }

    private nonisolated static func polishedQuestionText(
        _ question: String,
        answer: String,
        style: FlashcardPromptStyle,
        sourceText: String
    ) -> String {
        let cleanedQuestion = cleanupInlineText(question)

        if !questionNeedsRebuild(cleanedQuestion), isStudyQuestion(cleanedQuestion) {
            return normalizedQuestionEnding(cleanedQuestion)
        }

        if let concept = bestPromptConcept(
            question: cleanedQuestion,
            answer: answer,
            sourceText: sourceText
        ) {
            return questionTemplate(for: style, concept: concept)
        }

        return normalizedQuestionEnding(cleanedQuestion)
    }

    private nonisolated static func polishedAnswerText(_ answer: String) -> String {
        let cleanedAnswer = cleanupSpacing(in: answer)
        guard !cleanedAnswer.isEmpty else { return "" }
        guard !looksLikeFrontMatter(cleanedAnswer) else { return "" }
        guard !looksLikeAttributionText(cleanedAnswer) else { return "" }
        guard !looksLikeExercisePrompt(cleanedAnswer) else { return "" }

        if cleanedAnswer.contains("\n") {
            return cleanedAnswer
        }

        if cleanedAnswer.count > 280 || endsAbruptly(cleanedAnswer) {
            return compressedAnswer(
                from: cleanedAnswer,
                maximumSentences: 3,
                maximumCharacters: 260
            )
        }

        return ensureSentenceEnding(cleanedAnswer)
    }

    private nonisolated static func questionNeedsRebuild(_ question: String) -> Bool {
        let cleanedQuestion = cleanupInlineText(question)
        let loweredQuestion = cleanedQuestion.lowercased()

        if loweredQuestion.contains("??") || loweredQuestion.contains("?.") {
            return true
        }

        if let focusPhrase = questionFocusPhrase(from: cleanedQuestion),
           !isReasonableQuestionFocus(focusPhrase) {
            return true
        }

        let danglingEndings = [" between", " among", " of", " for", " in", " on", " with", ":"]
        if danglingEndings.contains(where: { loweredQuestion.hasSuffix($0) }) {
            return true
        }

        if loweredQuestion.hasPrefix("what does ") || loweredQuestion.hasPrefix("what do ") {
            let supportedActionWords = [
                " mean", " refer", " cause", " produce", " show", " contain",
                " include", " represent", " affect", " indicate", " convert", " form"
            ]

            return !supportedActionWords.contains(where: { loweredQuestion.contains($0) })
        }

        return false
    }

    private nonisolated static func bestPromptConcept(
        question: String,
        answer: String,
        sourceText: String
    ) -> String? {
        let evidence = sourceText.isEmpty
            ? ""
            : validatedEvidenceExcerpt(
                "",
                question: question,
                answer: answer,
                sourceText: sourceText
            )

        let rawCandidates: [String?] = [
            questionFocusPhrase(from: question),
            bestKeyword(in: answer, allowVerbs: false),
            bestKeyword(in: evidence, allowVerbs: false),
            bestKeyword(in: question, allowVerbs: false)
        ]
        let candidates = rawCandidates.compactMap { value -> String? in
            guard let value else { return nil }
            return cleanupInlineText(value)
        }

        for candidate in candidates {
            if isReasonableQuestionFocus(candidate) || isReasonablePrompt(candidate) {
                return candidate
            }
        }

        return nil
    }

    private nonisolated static func questionTemplate(
        for style: FlashcardPromptStyle,
        concept: String
    ) -> String {
        switch style {
        case .definition:
            return "What is \(concept)?"
        case .explanation:
            return "Explain \(concept)"
        case .why:
            return "Why is \(concept) important?"
        case .how:
            return "How does \(concept) work?"
        case .compare:
            return "Explain \(concept)"
        case .summary:
            return "What should you know about \(concept)?"
        }
    }

    private nonisolated static func normalizedQuestionEnding(_ question: String) -> String {
        let cleanedQuestion = cleanupInlineText(question)
        let loweredQuestion = cleanedQuestion.lowercased()

        if loweredQuestion.hasPrefix("explain ") || loweredQuestion.hasPrefix("compare ") {
            return cleanedQuestion
        }

        if cleanedQuestion.hasSuffix("?") {
            return cleanedQuestion
        }

        return "\(cleanedQuestion)?"
    }

    private nonisolated static func isCandidateStudySentence(_ sentence: String) -> Bool {
        let cleanedSentence = cleanupSpacing(in: sentence)
        let loweredSentence = cleanedSentence.lowercased()
        let words = cleanedSentence.split(separator: " ")
        let supportedMarkers = [
            " is ", " are ", " refers to ", " means ", " can be ", " used to ",
            " are used to ", " consists of ", " contains ", " includes "
        ]

        guard cleanedSentence.count >= 35, cleanedSentence.count <= 260 else { return false }
        guard words.count >= 7, words.count <= 36 else { return false }
        guard lettersRatio(in: cleanedSentence) > 0.6 else { return false }
        guard !looksLikeFrontMatter(cleanedSentence) else { return false }
        guard !looksLikeAttributionText(cleanedSentence) else { return false }
        guard !looksLikeExercisePrompt(cleanedSentence) else { return false }
        guard !endsAbruptly(cleanedSentence) else { return false }
        guard supportedMarkers.contains(where: { loweredSentence.contains($0) }) else { return false }

        return true
    }

    private nonisolated static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.count > 15 {
                sentences.append(sentence.trimmingCharacters(in: CharacterSet(charactersIn: ". ")))
            }
            return true
        }

        return sentences
    }

    private nonisolated static func compressedAnswer(
        from text: String,
        maximumSentences: Int = 2,
        maximumCharacters: Int = 220
    ) -> String {
        let normalized = normalizeText(text)
        guard !normalized.isEmpty else { return "" }

        let lines = normalized.components(separatedBy: .newlines)
        let bulletLikeLines = lines
            .compactMap { cleanedBulletItem(from: $0) }
            .filter { !looksLikeExercisePrompt($0) }

        if bulletLikeLines.count >= 2 {
            return bulletLikeLines
                .prefix(4)
                .map { "• \($0)" }
                .joined(separator: "\n")
        }

        let numberedLines = lines
            .compactMap { cleanedNumberedStep(from: $0) }
            .filter { !looksLikeExercisePrompt($0) }
        if numberedLines.count >= 2 {
            return numberedLines
                .prefix(4)
                .enumerated()
                .map { offset, step in
                    "\(offset + 1). \(step)"
                }
                .joined(separator: "\n")
        }

        let sentences = splitSentences(normalized)
        guard !sentences.isEmpty else {
            return completedSentencePrefix(normalized, limit: maximumCharacters)
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

        let answer = selectedSentences
            .map { sentence in
                ensureSentenceEnding(sentence)
            }
            .joined(separator: " ")

        return completedSentencePrefix(answer, limit: maximumCharacters)
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

    private nonisolated static func endsAbruptly(_ text: String) -> Bool {
        let cleanedText = cleanupInlineText(text)
        guard !cleanedText.isEmpty else { return true }
        guard !cleanedText.contains("\n") else { return false }

        let loweredText = cleanedText.lowercased()
        let trailingJoiners: Set<String> = [
            "and", "or", "because", "to", "for", "of", "in", "on", "with", "by",
            "from", "as", "that", "which", "while", "if", "when", "where", "using"
        ]
        let trailingWord = loweredText
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .last(where: { !$0.isEmpty }) ?? ""

        if trailingJoiners.contains(trailingWord) {
            return true
        }

        return loweredText.hasSuffix(",")
            || loweredText.hasSuffix(":")
            || loweredText.hasSuffix(";")
            || loweredText.hasSuffix("-")
    }

    private nonisolated static func sentencePriorityScore(for sentence: String) -> Int {
        let loweredSentence = sentence.lowercased()
        let tokensCount = Set(tokens(in: sentence)).count
        var score = tokensCount * 3

        let markers = [
            " because ", " refers to ", " means ", " is used to ", " helps ",
            " causes ", " compared ", " unlike ", " first ", " next ", " finally "
        ]

        for marker in markers where loweredSentence.contains(marker) {
            score += 8
        }

        if sentence.count >= 35 && sentence.count <= 180 {
            score += 6
        }

        return score
    }

    private nonisolated static func bestKeyword(in sentence: String, allowVerbs: Bool) -> String? {
        let tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass])
        tagger.string = sentence

        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        var candidates: [String] = []

        tagger.enumerateTags(
            in: sentence.startIndex..<sentence.endIndex,
            unit: .word,
            scheme: .nameTypeOrLexicalClass,
            options: options
        ) { tag, tokenRange in
            guard let tag else { return true }

            let token = String(sentence[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard token.count > 2 else { return true }

            switch tag {
            case .personalName, .placeName, .organizationName, .noun:
                if isUsefulKeyword(token) {
                    candidates.append(token)
                }
            case .verb:
                if allowVerbs && isUsefulKeyword(token) {
                    candidates.append(token)
                }
            default:
                break
            }

            return true
        }

        return candidates
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs < rhs
                }
                return lhs.count > rhs.count
            }
            .first(where: isSpecificStudyConcept)
    }

    private nonisolated static func tokens(in text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && isUsefulKeyword($0) }
    }

    private nonisolated static func isUsefulKeyword(_ token: String) -> Bool {
        !stopWords.contains(token.lowercased())
    }

    private nonisolated static func isReasonablePrompt(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 2
            && trimmed.count <= 55
            && !trimmed.contains("?")
            && !looksLikeFrontMatter(trimmed)
            && !looksLikeAttributionText(trimmed)
            && !isStructuralHeading(trimmed)
            && isSpecificStudyConcept(trimmed)
            && lettersRatio(in: trimmed) > 0.55
    }

    private nonisolated static func isLikelyHeading(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        return text.count <= 48
            && words.count <= 6
            && !text.contains(":")
            && !text.contains("?")
            && !looksLikeFrontMatter(text)
            && !isStructuralHeading(text)
    }

    private nonisolated static func inferredStyle(from question: String) -> FlashcardPromptStyle {
        let loweredQuestion = question.lowercased()

        if loweredQuestion.hasPrefix("why ") {
            return .why
        }

        if loweredQuestion.hasPrefix("how ") || loweredQuestion.hasPrefix("when ") {
            return .how
        }

        if loweredQuestion.contains("compare") || loweredQuestion.contains("difference") {
            return .compare
        }

        if loweredQuestion.hasPrefix("what is ") || loweredQuestion.hasPrefix("what are ") {
            return .definition
        }

        if loweredQuestion.hasPrefix("explain ") {
            return .explanation
        }

        return .summary
    }

    private nonisolated static func isBulletLine(_ line: String) -> Bool {
        cleanedBulletItem(from: line) != nil
    }

    private nonisolated static func isNumberedStep(_ line: String) -> Bool {
        cleanedNumberedStep(from: line) != nil
    }

    private nonisolated static func cleanedBulletItem(from line: String) -> String? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else { return nil }

        let bulletPrefixes = ["- ", "• ", "* "]
        for prefix in bulletPrefixes where trimmedLine.hasPrefix(prefix) {
            return String(trimmedLine.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private nonisolated static func cleanedNumberedStep(from line: String) -> String? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else { return nil }

        let numberedPattern = #"^\d+[\.\)]\s+"#
        guard let regex = try? NSRegularExpression(pattern: numberedPattern) else { return nil }
        let range = NSRange(trimmedLine.startIndex..<trimmedLine.endIndex, in: trimmedLine)

        if let match = regex.firstMatch(in: trimmedLine, options: [], range: range),
           let matchRange = Range(match.range, in: trimmedLine) {
            return String(trimmedLine[matchRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private nonisolated static func curatedStudyText(
        from text: String,
        maximumLineCount: Int = 260,
        minimumBlockScore: Int = 8,
        maximumCharacters: Int = 14_000
    ) -> String {
        let normalizedInput = repairWrappedWords(in: text.replacingOccurrences(of: "\r", with: "\n"))
        let blocks = normalizedInput
            .components(separatedBy: "\n\n")
            .compactMap { rawBlock in
                let cleanedLines = studyLines(from: rawBlock)
                let cleanedBlock = normalizeText(cleanedLines.joined(separator: "\n"))
                return cleanedBlock.isEmpty ? nil : cleanedBlock
            }
            .filter { !$0.isEmpty }

        let scoredBlocks = blocks.enumerated().compactMap { (element: EnumeratedSequence<[String]>.Element) -> RankedStudyChunk? in
            let index = element.offset
            let block = element.element
            let score = studyScore(for: block)
            guard score >= minimumBlockScore else { return nil }
            return RankedStudyChunk(orderIndex: index, text: block, score: score)
        }

        let selectedBlocks = prioritizedChunks(
            from: scoredBlocks,
            maximumCount: 12,
            maximumCharacters: maximumCharacters
        )
        if !selectedBlocks.isEmpty {
            return normalizeText(selectedBlocks.map { $0.text }.joined(separator: "\n\n"))
        }

        let filteredLines = Array(studyLines(from: normalizedInput).prefix(maximumLineCount))
        return normalizeText(filteredLines.joined(separator: "\n"))
    }

    private nonisolated static func wholeDocumentStudyText(
        from chunks: [RankedStudyChunk],
        fallbackText: String,
        maximumCharacters: Int
    ) -> String {
        let orderedChunks = chunks.sorted { $0.orderIndex < $1.orderIndex }
        let fullCuratedText = normalizeText(orderedChunks.map { $0.text }.joined(separator: "\n\n"))

        if !fullCuratedText.isEmpty, fullCuratedText.count <= maximumCharacters {
            return fullCuratedText
        }

        let chapterBalancedText = chapterBalancedStudyText(
            from: orderedChunks,
            maximumCharacters: maximumCharacters
        )
        if !chapterBalancedText.isEmpty {
            return chapterBalancedText
        }

        let balancedText = normalizeText(
            prioritizedChunks(
                from: orderedChunks,
                maximumCount: 18,
                maximumCharacters: maximumCharacters
            )
            .map { $0.text }
            .joined(separator: "\n\n")
        )

        if !balancedText.isEmpty {
            return balancedText
        }

        return curatedStudyText(
            from: fallbackText,
            maximumLineCount: 520,
            minimumBlockScore: 5,
            maximumCharacters: maximumCharacters
        )
    }

    private nonisolated static func chapterBalancedStudyText(
        from chunks: [RankedStudyChunk],
        maximumCharacters: Int
    ) -> String {
        let chapterGroups = groupedChapterChunks(from: chunks)
        guard chapterGroups.count >= 3 else { return "" }

        let chapterBudget = max(700, maximumCharacters / max(chapterGroups.count, 1))
        var selectedSections: [String] = []
        var totalCharacters = 0

        for group in chapterGroups {
            guard let strongestChunk = group.chunks.max(by: { $0.score < $1.score }) else {
                continue
            }

            let chapterText = completedSentencePrefix(
                strongestChunk.text,
                limit: min(chapterBudget, 1_400)
            )
            let section = normalizeText("\(group.title)\n\(chapterText)")
            guard !section.isEmpty else { continue }

            if !selectedSections.isEmpty, totalCharacters + section.count > maximumCharacters {
                continue
            }

            selectedSections.append(section)
            totalCharacters += section.count
        }

        return normalizeText(selectedSections.joined(separator: "\n\n"))
    }

    private nonisolated static func groupedChapterChunks(
        from chunks: [RankedStudyChunk]
    ) -> [(title: String, chunks: [RankedStudyChunk])] {
        var groups: [(title: String, chunks: [RankedStudyChunk])] = []

        for chunk in chunks {
            guard let chapterTitle = chunk.chapterTitle else { continue }

            if let lastIndex = groups.indices.last,
               groups[lastIndex].title == chapterTitle {
                groups[lastIndex].chunks.append(chunk)
            } else {
                groups.append((title: chapterTitle, chunks: [chunk]))
            }
        }

        return groups
    }

    private nonisolated static func prioritizedChunks(
        from chunks: [RankedStudyChunk],
        maximumCount: Int,
        maximumCharacters: Int
    ) -> [RankedStudyChunk] {
        let orderedChunks = chunks.sorted { $0.orderIndex < $1.orderIndex }
        guard orderedChunks.count > maximumCount else {
            return chunksFittingLimit(orderedChunks, maximumCharacters: maximumCharacters)
        }

        let bucketCount = min(maximumCount, 6)
        var selected: [RankedStudyChunk] = []
        var selectedOrderIndexes = Set<Int>()
        var totalCharacters = 0

        for bucketIndex in 0..<bucketCount {
            let startIndex = bucketIndex * orderedChunks.count / bucketCount
            let endIndex = (bucketIndex + 1) * orderedChunks.count / bucketCount
            let bucket = Array(orderedChunks[startIndex..<endIndex])

            guard let bestBucketChunk = bucket.max(by: { $0.score < $1.score }) else {
                continue
            }

            addChunkIfPossible(
                bestBucketChunk,
                to: &selected,
                selectedOrderIndexes: &selectedOrderIndexes,
                totalCharacters: &totalCharacters,
                maximumCount: maximumCount,
                maximumCharacters: maximumCharacters
            )
        }

        let sortedChunks = orderedChunks.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.orderIndex < rhs.orderIndex
            }
            return lhs.score > rhs.score
        }

        for chunk in sortedChunks {
            addChunkIfPossible(
                chunk,
                to: &selected,
                selectedOrderIndexes: &selectedOrderIndexes,
                totalCharacters: &totalCharacters,
                maximumCount: maximumCount,
                maximumCharacters: maximumCharacters
            )

            if selected.count == maximumCount {
                break
            }
        }

        return selected.sorted { $0.orderIndex < $1.orderIndex }
    }

    private nonisolated static func chunksFittingLimit(
        _ chunks: [RankedStudyChunk],
        maximumCharacters: Int
    ) -> [RankedStudyChunk] {
        var selected: [RankedStudyChunk] = []
        var totalCharacters = 0

        for chunk in chunks {
            if !selected.isEmpty && totalCharacters + chunk.text.count > maximumCharacters {
                break
            }

            selected.append(chunk)
            totalCharacters += chunk.text.count
        }

        return selected
    }

    private nonisolated static func addChunkIfPossible(
        _ chunk: RankedStudyChunk,
        to selected: inout [RankedStudyChunk],
        selectedOrderIndexes: inout Set<Int>,
        totalCharacters: inout Int,
        maximumCount: Int,
        maximumCharacters: Int
    ) {
        guard selected.count < maximumCount else { return }
        guard !selectedOrderIndexes.contains(chunk.orderIndex) else { return }

        if !selected.isEmpty && totalCharacters + chunk.text.count > maximumCharacters {
            return
        }

        selected.append(chunk)
        selectedOrderIndexes.insert(chunk.orderIndex)
        totalCharacters += chunk.text.count
    }

    private nonisolated static func studyLines(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { isStudyLine($0) }
    }

    private nonisolated static func studyScore(for text: String) -> Int {
        let normalizedText = normalizeText(text)
        guard !normalizedText.isEmpty else { return Int.min }
        guard !looksLikeFrontMatter(normalizedText) else { return -40 }

        let loweredText = normalizedText.lowercased()
        let words = normalizedText.split(separator: " ")
        let lines = normalizedText.components(separatedBy: .newlines)
        let conceptCount = Set(tokens(in: normalizedText)).count
        let candidateSentenceCount = splitSentences(normalizedText).filter(isCandidateStudySentence).count
        let attributionLineCount = lines.filter(looksLikeAttributionText).count
        let hasStructuredSignal = normalizedText.contains(":")
            || normalizedText.contains("?")
            || normalizedText.contains("•")
            || loweredText.contains("- ")
            || normalizedText.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) != nil
            || normalizedText.range(of: #"\n\d+[\.\)]\s+"#, options: .regularExpression) != nil
            || candidateSentenceCount > 0

        var score = 0

        if words.count >= 8 && words.count <= 180 {
            score += 16
        } else if words.count > 180 {
            score += 8
        } else {
            score -= 10
        }

        if normalizedText.contains(":") {
            score += 10
        }

        if normalizedText.contains("?") {
            score += 8
        }

        if normalizedText.contains("•") || loweredText.contains("- ") {
            score += 12
        }

        if normalizedText.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) != nil
            || normalizedText.range(of: #"\n\d+[\.\)]\s+"#, options: .regularExpression) != nil {
            score += 12
        }

        if !hasStructuredSignal {
            score -= 24
        }

        let studyMarkers = [
            " is ", " are ", " refers to ", " means ", " because ", " therefore ",
            " used to ", " causes ", " compared", " unlike ", " first ", " next ", " finally ",
            " process ", " function ", " definition "
        ]

        for marker in studyMarkers where loweredText.contains(marker) {
            score += 6
        }

        if lines.count >= 2 {
            score += min(lines.count * 2, 12)
        }

        if conceptCount >= 6 {
            score += 10
        } else if conceptCount >= 3 {
            score += 5
        }

        score += min(candidateSentenceCount * 8, 32)

        if lettersRatio(in: normalizedText) > 0.7 {
            score += 8
        } else if lettersRatio(in: normalizedText) > 0.5 {
            score += 3
        } else {
            score -= 8
        }

        if normalizedText == normalizedText.uppercased(), normalizedText.count < 90 {
            score -= 12
        }

        if looksLikeExercisePrompt(normalizedText) {
            score -= 28
        }

        if looksLikeAttributionText(normalizedText) {
            score -= 80
        }

        if attributionLineCount > 0 {
            score -= attributionLineCount * 24
        }

        if attributionLineCount >= max(2, lines.count / 2) {
            score -= 80
        }

        return score
    }

    private nonisolated static func isStudyQuestion(_ question: String) -> Bool {
        let loweredQuestion = question.lowercased()
        guard let focusPhrase = questionFocusPhrase(from: question) else { return false }
        return question.count >= 8
            && question.count <= 140
            && !looksLikeFrontMatter(question)
            && !looksLikeAttributionText(question)
            && !looksLikeExercisePrompt(question)
            && !loweredQuestion.contains("cover page")
            && !loweredQuestion.contains("table of contents")
            && isReasonableQuestionFocus(focusPhrase)
    }

    private nonisolated static func isStudyAnswer(_ answer: String) -> Bool {
        let lines = normalizeText(answer).components(separatedBy: .newlines).filter { !$0.isEmpty }

        return answer.count >= 10
            && answer.count <= 420
            && !looksLikeFrontMatter(answer)
            && !looksLikeAttributionText(answer)
            && !looksLikeExercisePrompt(answer)
            && !lines.allSatisfy { looksLikeExercisePrompt($0) }
            && !endsAbruptly(answer)
            && lettersRatio(in: answer) > 0.5
    }

    private nonisolated static func isStudyLine(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLine.count >= 4 else { return false }
        guard lettersRatio(in: trimmedLine) > 0.35 else { return false }
        guard !looksLikeFrontMatter(trimmedLine) else { return false }
        guard !looksLikeAttributionText(trimmedLine) else { return false }
        guard !looksLikeExercisePrompt(trimmedLine) else { return false }

        if trimmedLine.range(of: #"^page\s+\d+$"#, options: .regularExpression) != nil {
            return false
        }

        if trimmedLine.range(of: #"^\d+$"#, options: .regularExpression) != nil {
            return false
        }

        return true
    }

    private nonisolated static func isStudyParagraph(_ paragraph: String) -> Bool {
        let words = paragraph.split(separator: " ")
        return words.count >= 16
            && words.count <= 120
            && !looksLikeFrontMatter(paragraph)
            && !looksLikeAttributionText(paragraph)
            && lettersRatio(in: paragraph) > 0.5
    }

    private nonisolated static func looksLikeFrontMatter(_ text: String) -> Bool {
        let loweredText = text.lowercased()
        let strongFrontMatterKeywords = [
            "dedicated to the memory", "table of contents", "acknowledgements",
            "review questions", "discussion questions", "chapter objectives",
            "learning objectives", "all rights reserved"
        ]
        let frontMatterKeywords = [
            "table of contents", "contents", "student name", "student number", "module code",
            "module title", "course code", "assignment", "submitted by", "prepared by",
            "all rights reserved", "copyright", "acknowledgements", "bibliography",
            "references", "appendix", "lecturer", "university", "department",
            "dedicated to", "review questions", "discussion questions",
            "chapter objectives", "learning objectives", "exercise"
        ]

        if looksLikeAttributionText(text) {
            return true
        }

        if strongFrontMatterKeywords.contains(where: { loweredText.contains($0) }) {
            return true
        }

        let matchedKeywords = frontMatterKeywords.filter { loweredText.contains($0) }.count
        if matchedKeywords >= 2 {
            return true
        }

        if loweredText.range(of: #"^page\s+\d+$"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    private nonisolated static func isStructuralHeading(_ text: String) -> Bool {
        let loweredText = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let blockedHeadings: Set<String> = [
            "contents", "table of contents", "overview", "introduction", "summary",
            "conclusion", "references", "bibliography", "acknowledgements",
            "appendix", "learning outcomes"
        ]

        return blockedHeadings.contains(loweredText) || loweredText.hasPrefix("why study ")
    }

    private nonisolated static func detectedChapterTitle(in text: String) -> String? {
        let chapterPatterns = [
            #"^\d+\s*•\s*Chapter\s+\d+\s*/\s*[^.]{3,80}$"#,
            #"^Chapter\s+\d+\s*/\s*[^.]{3,80}$"#,
            #"^Chapter\s+\d+\s+[^.]{3,80}$"#
        ]

        for rawLine in text.components(separatedBy: .newlines) {
            let line = cleanupInlineText(rawLine)
            guard !line.isEmpty else { continue }

            for pattern in chapterPatterns where line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return normalizedChapterTitle(line)
            }
        }

        return nil
    }

    private nonisolated static func normalizedChapterTitle(_ title: String) -> String {
        let withoutPageNumber = title.replacingOccurrences(
            of: #"^\d+\s*•\s*"#,
            with: "",
            options: .regularExpression
        )

        return cleanupInlineText(withoutPageNumber)
    }

    private nonisolated static func questionFocusPhrase(from question: String) -> String? {
        let cleanedQuestion = cleanupInlineText(question)
        let loweredQuestion = cleanedQuestion.lowercased()
        let templates: [(prefix: String, suffix: String?)] = [
            ("what are the key points about ", "?"),
            ("what should you understand about ", "?"),
            ("what should you know about ", "?"),
            ("how is ", " used in practice?"),
            ("how does ", " work?"),
            ("why is ", " important?"),
            ("what does ", "?"),
            ("what do ", "?"),
            ("what is ", "?"),
            ("what are ", "?"),
            ("how do ", "?"),
            ("how is ", "?"),
            ("how are ", "?"),
            ("why are ", "?"),
            ("explain ", nil),
            ("compare ", nil)
        ]

        for template in templates {
            guard loweredQuestion.hasPrefix(template.prefix) else { continue }

            let startIndex = cleanedQuestion.index(
                cleanedQuestion.startIndex,
                offsetBy: template.prefix.count
            )
            var focus = String(cleanedQuestion[startIndex...])

            if let suffix = template.suffix,
               focus.lowercased().hasSuffix(suffix) {
                focus = String(focus.dropLast(suffix.count))
            } else if cleanedQuestion.hasSuffix("?") {
                focus = String(focus.dropLast())
            }

            let cleanedFocus = cleanupInlineText(focus)
            if !cleanedFocus.isEmpty {
                return cleanedFocus
            }
        }

        return nil
    }

    private nonisolated static func isReasonableQuestionFocus(_ text: String) -> Bool {
        let cleanedText = cleanupInlineText(text)
        let loweredText = cleanedText.lowercased()
        let words = loweredText
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        let blockedEdgeWords: Set<String> = [
            "a", "an", "the", "to", "for", "of", "in", "on", "by", "from",
            "with", "and", "or", "each", "every", "this", "that", "these", "those"
        ]
        let blockedTrailingWords: Set<String> = ["each", "following", "above", "below", "other", "between", "among"]
        let blockedPhrases = [
            "for each", "of each", "schematic sketch", "characteristics for",
            "review questions", "chapter objectives", "learning objectives",
            "table of contents", "dedicated to"
        ]

        guard cleanedText.count >= 3, cleanedText.count <= 80 else { return false }
        guard words.count >= 1, words.count <= 10 else { return false }
        guard lettersRatio(in: cleanedText) > 0.55 else { return false }
        guard !looksLikeFrontMatter(cleanedText), !looksLikeAttributionText(cleanedText), !looksLikeExercisePrompt(cleanedText) else { return false }
        guard let firstWord = words.first, let lastWord = words.last else { return false }
        guard !blockedEdgeWords.contains(firstWord), !blockedEdgeWords.contains(lastWord) else { return false }
        guard !blockedTrailingWords.contains(lastWord) else { return false }
        guard !blockedPhrases.contains(where: { loweredText.contains($0) }) else { return false }
        guard isSpecificStudyConcept(cleanedText) else { return false }

        return true
    }

    private nonisolated static func looksLikeAttributionText(_ text: String) -> Bool {
        let cleanedText = cleanupInlineText(text)
        let loweredText = cleanedText.lowercased()
        let creditMarkers = [
            "istockphoto", "alamy", "shutterstock", "getty", "courtesy of", "image credit",
            "photo credit", "photograph by", "photo by", "image by", "cover image",
            "cover design", "illustration by", "©", "all rights reserved",
            "in memory of", "father, lumberman, and friend"
        ]
        let shortStructuralPattern = #"^(chapter|part|section)\s+\d+\b"#
        let titleCaseNamePattern = #"^[A-Z][a-z]+(?:\s+[A-Z][a-z]+){2,3}$"#
        let slashCreditPattern = #"[A-Za-z]+/[A-Za-z]"#
        let shortWords = cleanedText.split(separator: " ")

        if creditMarkers.contains(where: { loweredText.contains($0) }) {
            return true
        }

        if cleanedText.range(of: shortStructuralPattern, options: .regularExpression) != nil,
           cleanedText.count <= 40 {
            return true
        }

        if cleanedText.range(of: slashCreditPattern, options: .regularExpression) != nil,
           cleanedText.count <= 80 {
            return true
        }

        if cleanedText.range(of: titleCaseNamePattern, options: .regularExpression) != nil,
           cleanedText.count <= 50,
           looksLikeShortPersonCredit(shortWords) {
            return true
        }

        if cleanedText.contains(","),
           shortWords.count <= 8,
           shortWords.filter({ $0.first?.isUppercase == true }).count >= 3 {
            return true
        }

        return false
    }

    private nonisolated static func looksLikeShortPersonCredit(_ words: [Substring]) -> Bool {
        let commonFirstNames: Set<String> = [
            "peter", "joseph", "william", "john", "mary", "james", "robert",
            "michael", "david", "richard", "charles", "thomas", "christopher",
            "daniel", "paul", "mark", "george", "susan", "sarah", "elizabeth"
        ]
        let loweredWords = words.map { $0.lowercased() }

        return loweredWords.contains(where: { commonFirstNames.contains($0) })
    }

    private nonisolated static func isSpecificStudyConcept(_ text: String) -> Bool {
        let cleanedText = cleanupInlineText(text)
        let words = cleanedText
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let blockedGenericConcepts: Set<String> = [
            "properties", "property", "differences", "difference", "expression", "expressions",
            "material", "materials", "item", "items", "thing", "things", "example", "examples",
            "chapter", "introduction", "section", "problem", "problems", "equation", "equations",
            "process", "processes", "function", "functions", "system", "systems", "type", "types"
        ]

        guard !cleanedText.isEmpty else { return false }
        guard !looksLikeAttributionText(cleanedText) else { return false }
        guard let lastWord = words.last else { return false }

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

    private nonisolated static func looksLikeExercisePrompt(_ text: String) -> Bool {
        let cleanedText = cleanupInlineText(text)
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

    private nonisolated static func cleanupSpacing(in text: String) -> String {
        text
            .replacingOccurrences(of: "  ", with: " ")
            .replacingOccurrences(of: "\n\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func normalizeText(_ text: String) -> String {
        repairWrappedWords(in: text)
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private nonisolated static func cleanupInlineText(_ text: String) -> String {
        cleanupSpacing(
            in: repairWrappedWords(in: text)
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "?.", with: "?")
        )
    }

    private nonisolated static func repairWrappedWords(in text: String) -> String {
        text.replacingOccurrences(
            of: #"([A-Za-z]{2,})-\s*\n\s*([A-Za-z]{2,})"#,
            with: "$1$2",
            options: .regularExpression
        )
    }

    private nonisolated static func containsNormalizedSnippet(_ snippet: String, in text: String) -> Bool {
        let normalizedSnippet = normalizedMatchText(snippet)
        let normalizedSource = normalizedMatchText(text)

        guard !normalizedSnippet.isEmpty, !normalizedSource.isEmpty else {
            return false
        }

        return normalizedSource.contains(normalizedSnippet)
    }

    private nonisolated static func normalizedMatchText(_ text: String) -> String {
        cleanupInlineText(text)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private nonisolated static let stopWords: Set<String> = [
        "the", "and", "with", "from", "that", "this", "these", "those",
        "have", "has", "had", "into", "their", "there", "which", "what",
        "when", "where", "whose", "your", "about", "because", "through",
        "using", "used", "also", "than", "then", "them", "they", "will",
        "shall", "could", "would", "should"
    ]
}
