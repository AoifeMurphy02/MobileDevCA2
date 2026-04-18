//
//  FlashcardImportService.swift
//  CA2ISOApp
//
//  Created by Meghana on 17/04/2026.
//

import Foundation
import NaturalLanguage
import PDFKit
import PhotosUI
import SwiftUI
import UIKit
import Vision

enum FlashcardImportError: LocalizedError {
    case unreadableFile
    case unsupportedFile
    case imageLoadFailed
    case textExtractionFailed
    case emptyContent

    var errorDescription: String? {
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
            return "No readable text was found, so no flashcards were created."
        }
    }
}

struct ImportedFlashcardContent: Sendable {
    let title: String
    let sourceType: String
    let text: String
}

private struct RankedStudyChunk: Sendable {
    let orderIndex: Int
    let text: String
    let score: Int

    nonisolated init(orderIndex: Int, text: String, score: Int) {
        self.orderIndex = orderIndex
        self.text = text
        self.score = score
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
            return ImportedFlashcardContent(title: url.deletingPathExtension().lastPathComponent, sourceType: "Imported Image", text: text)
        }

        throw FlashcardImportError.unsupportedFile
    }

    nonisolated static func importPhoto(from item: PhotosPickerItem) async throws -> ImportedFlashcardContent {
        guard let data = try await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            throw FlashcardImportError.imageLoadFailed
        }

        let text = try await extractText(from: [image])
        return ImportedFlashcardContent(title: "Photo Flashcards", sourceType: "Photo Library", text: text)
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
        let draftDeck = try buildDraftDeck(
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
        let normalizedOriginalText = normalizeText(text)
        guard !normalizedOriginalText.isEmpty else {
            throw FlashcardImportError.emptyContent
        }

        let prioritizedText = curatedStudyText(from: text)
        var workingText = prioritizedText.isEmpty ? normalizedOriginalText : prioritizedText
        var generatedDrafts = makeDrafts(from: workingText)

        if generatedDrafts.isEmpty && workingText != normalizedOriginalText {
            workingText = normalizedOriginalText
            generatedDrafts = makeDrafts(from: workingText)
        }

        let drafts = sanitizedDrafts(
            FlashcardAIEnhancer.finalizeDrafts(
                generatedDrafts,
                sourceText: workingText
            )
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
            cards: drafts
        )
    }

    nonisolated static func buildSet(from draftDeck: FlashcardDeckDraft) throws -> FlashcardSet {
        let drafts = sanitizedDrafts(draftDeck.cards)
        guard !drafts.isEmpty else {
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
                ? drafts.map { "\($0.question)\n\($0.answer)" }.joined(separator: "\n")
                : draftDeck.rawText
        )

        let flashcardSet = FlashcardSet(
            title: resolvedTitle,
            sourceType: resolvedSourceType,
            subject: resolvedSubject,
            topic: resolvedTopic,
            rawText: resolvedRawText
        )

        flashcardSet.cards = drafts.enumerated().map { index, draft in
            Flashcard(
                question: draft.question,
                answer: draft.answer,
                orderIndex: index,
                parentSet: flashcardSet
            )
        }

        return flashcardSet
    }

    private nonisolated static func importPDF(from url: URL) throws -> ImportedFlashcardContent {
        guard let document = PDFDocument(url: url) else {
            throw FlashcardImportError.unreadableFile
        }

        let scoredPages: [RankedStudyChunk] = (0..<document.pageCount).compactMap { (pageIndex: Int) -> RankedStudyChunk? in
            guard let rawPageText = document.page(at: pageIndex)?.string else {
                return nil
            }

            let curatedPageText = curatedStudyText(
                from: rawPageText,
                maximumLineCount: 70,
                minimumBlockScore: 10,
                maximumCharacters: 1_800
            )
            let resolvedPageText = curatedPageText.isEmpty ? normalizeText(rawPageText) : curatedPageText
            guard !resolvedPageText.isEmpty else { return nil }

            let score = studyScore(for: resolvedPageText)
            guard score > 0 else { return nil }

            return RankedStudyChunk(orderIndex: pageIndex, text: resolvedPageText, score: score)
        }

        let selectedPages = prioritizedChunks(
            from: scoredPages,
            maximumCount: 10,
            maximumCharacters: 16_000
        )
        let joinedText = normalizeText(selectedPages.map { $0.text }.joined(separator: "\n\n"))
        let fallbackText = normalizeText(
            (0..<min(document.pageCount, 6))
                .compactMap { (pageIndex: Int) -> String? in
                    document.page(at: pageIndex)?.string
                }
                .joined(separator: "\n\n")
        )
        let resolvedText = joinedText.isEmpty ? fallbackText : joinedText
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

        let curatedText = curatedStudyText(from: text)
        let resolvedText = curatedText.isEmpty ? normalizeText(text) : curatedText
        guard !resolvedText.isEmpty else {
            throw FlashcardImportError.textExtractionFailed
        }

        return ImportedFlashcardContent(
            title: url.deletingPathExtension().lastPathComponent,
            sourceType: "Text File",
            text: resolvedText
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
        let filteredLines = studyLines(from: text)
        let normalizedLines = filteredLines.isEmpty
            ? text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            : filteredLines

        var drafts: [FlashcardDraft] = []
        var seenPairs = Set<String>()

        for draft in extractDefinitionPairs(from: normalizedLines) {
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

        for draft in extractHeadingContextCards(from: normalizedLines) {
            appendDraft(draft, to: &drafts, seenPairs: &seenPairs)
        }

        for draft in extractSentenceBasedCards(from: text) {
            appendDraft(draft, to: &drafts, seenPairs: &seenPairs)
        }

        if drafts.isEmpty {
            for draft in fallbackCards(from: normalizedLines) {
                appendDraft(draft, to: &drafts, seenPairs: &seenPairs)
            }
        }

        return Array(drafts.prefix(36))
    }

    private nonisolated static func sanitizedDrafts(_ drafts: [FlashcardDraft]) -> [FlashcardDraft] {
        var sanitized: [FlashcardDraft] = []
        var seenPairs = Set<String>()

        for draft in drafts {
            let normalizedQuestion = draft.question.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedAnswer = draft.answer.trimmingCharacters(in: .whitespacesAndNewlines)

            guard normalizedQuestion.count > 6, normalizedAnswer.count > 6 else { continue }
            guard isStudyQuestion(normalizedQuestion), isStudyAnswer(normalizedAnswer) else { continue }

            let key = "\(normalizedQuestion.lowercased())|\(normalizedAnswer.lowercased())"
            guard !seenPairs.contains(key) else { continue }

            seenPairs.insert(key)
            sanitized.append(
                FlashcardDraft(
                    id: draft.id,
                    question: normalizedQuestion,
                    answer: normalizedAnswer,
                    style: draft.style
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
        let normalizedQuestion = draft.question.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAnswer = draft.answer.trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalizedQuestion.count > 6, normalizedAnswer.count > 6 else { return }
        guard isStudyQuestion(normalizedQuestion), isStudyAnswer(normalizedAnswer) else { return }

        let key = "\(normalizedQuestion.lowercased())|\(normalizedAnswer.lowercased())"
        guard !seenPairs.contains(key) else { return }

        seenPairs.insert(key)
        drafts.append(
            FlashcardDraft(
                id: draft.id,
                question: normalizedQuestion,
                answer: normalizedAnswer,
                style: draft.style
            )
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
                if details.count == 3 || combinedCount > 260 {
                    break
                }

                lookAheadIndex += 1
            }

            let detail = details.joined(separator: " ")
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
                        answer: numberedSteps.enumerated().map { index, step in
                            "\(index + 1). \(step)"
                        }.joined(separator: "\n"),
                        style: .how
                    )
                )
            }

            index = max(index + 1, lookAheadIndex)
        }

        return drafts
    }

    private nonisolated static func draftFromDelimitedLine(_ line: String) -> FlashcardDraft? {
        let delimiters = [":", " - ", " – ", " — "]

        for delimiter in delimiters {
            let parts = line.components(separatedBy: delimiter)
            guard parts.count == 2 else { continue }

            let term = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let definition = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

            guard isReasonablePrompt(term), definition.count > 8 else { continue }

            return FlashcardDraft(
                question: "What is \(term)?",
                answer: definition,
                style: .definition
            )
        }

        return nil
    }

    private nonisolated static func extractQuestionAnswerPairs(from lines: [String]) -> [FlashcardDraft] {
        guard lines.count > 1 else { return [] }
        var drafts: [FlashcardDraft] = []

        for index in 0..<(lines.count - 1) {
            let questionLine = lines[index]
            let answerLine = lines[index + 1]

            guard questionLine.hasSuffix("?"), answerLine.count > 2 else { continue }
            drafts.append(
                FlashcardDraft(
                    question: questionLine,
                    answer: answerLine,
                    style: inferredStyle(from: questionLine)
                )
            )
        }

        return drafts
    }

    private nonisolated static func extractSentenceBasedCards(from text: String) -> [FlashcardDraft] {
        let sentences = Array(splitSentences(text).prefix(48))
        var drafts: [FlashcardDraft] = []

        for sentence in sentences {
            if let draft = makeProcessCard(from: sentence) {
                drafts.append(draft)
                continue
            }

            if let draft = makeComparisonCard(from: sentence) {
                drafts.append(draft)
                continue
            }

            if let draft = makeDefinitionSentenceCard(from: sentence) {
                drafts.append(draft)
                continue
            }

            if let draft = makeCauseEffectCard(from: sentence) {
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
            #"^(.{2,50}?)\s+is\s+(.{8,220})$"#,
            #"^(.{2,50}?)\s+are\s+(.{8,220})$"#,
            #"^(.{2,50}?)\s+refers to\s+(.{8,220})$"#,
            #"^(.{2,50}?)\s+means\s+(.{8,220})$"#,
            #"^(.{2,50}?)\s+can be defined as\s+(.{8,220})$"#
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

            guard isReasonablePrompt(term) else { continue }

            return FlashcardDraft(
                question: "What is \(term)?",
                answer: definition.trimmingCharacters(in: CharacterSet(charactersIn: ". ")),
                style: .definition
            )
        }

        return nil
    }

    private nonisolated static func makeProcessCard(from sentence: String) -> FlashcardDraft? {
        let loweredSentence = sentence.lowercased()
        let processMarkers = ["first", "next", "then", "finally", "after that"]
        let markerCount = processMarkers.filter { loweredSentence.contains($0) }.count

        guard markerCount >= 2,
              let concept = bestKeyword(in: sentence, allowVerbs: false) else {
            return nil
        }

        return FlashcardDraft(
            question: "How does \(concept) happen?",
            answer: sentence,
            style: .how
        )
    }

    private nonisolated static func makeComparisonCard(from sentence: String) -> FlashcardDraft? {
        let loweredSentence = sentence.lowercased()
        let markers = [" whereas ", " unlike ", " compared with ", " compared to ", " in contrast to "]

        for marker in markers {
            guard let range = loweredSentence.range(of: marker) else { continue }

            let leftSide = sentence[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let rightSide = sentence[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)

            guard let leftKeyword = bestKeyword(in: String(leftSide), allowVerbs: false),
                  let rightKeyword = bestKeyword(in: String(rightSide), allowVerbs: false),
                  leftKeyword.lowercased() != rightKeyword.lowercased() else {
                continue
            }

            return FlashcardDraft(
                question: "How does \(leftKeyword) compare with \(rightKeyword)?",
                answer: sentence,
                style: .compare
            )
        }

        return nil
    }

    private nonisolated static func makeCauseEffectCard(from sentence: String) -> FlashcardDraft? {
        let loweredSentence = sentence.lowercased()

        if let range = loweredSentence.range(of: " because ") {
            let effect = sentence[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let cause = sentence[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)

            guard effect.count > 8, cause.count > 8 else { return nil }

            return FlashcardDraft(
                question: "Why \(effect.lowercased())?",
                answer: "Because \(cause).",
                style: .why
            )
        }

        return nil
    }

    private nonisolated static func makePurposeCard(from sentence: String) -> FlashcardDraft? {
        let patterns = [
            #"^(.{2,60}?)\s+is used to\s+(.{8,220})$"#,
            #"^(.{2,60}?)\s+are used to\s+(.{8,220})$"#,
            #"^(.{2,60}?)\s+helps\s+(.{8,220})$"#
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

            guard isReasonablePrompt(subject), remainder.count > 8 else { continue }

            return FlashcardDraft(
                question: "What is \(subject) used for?",
                answer: remainder.trimmingCharacters(in: CharacterSet(charactersIn: ". ")),
                style: .how
            )
        }

        return nil
    }

    private nonisolated static func makeFactCard(from sentence: String) -> FlashcardDraft? {
        guard sentence.count > 25, sentence.count < 220 else { return nil }
        guard let keyword = bestKeyword(in: sentence, allowVerbs: false) else { return nil }

        return FlashcardDraft(
            question: "What is one key thing to remember about \(keyword)?",
            answer: sentence,
            style: .summary
        )
    }

    private nonisolated static func fallbackCards(from lines: [String]) -> [FlashcardDraft] {
        Array(
            lines
                .filter { isStudyLine($0) }
                .sorted { studyScore(for: $0) > studyScore(for: $1) }
                .prefix(10)
                .compactMap { (line: String) -> FlashcardDraft? in
                    guard let keyword = bestKeyword(in: line, allowVerbs: false),
                          isReasonablePrompt(keyword) else {
                        return nil
                    }

                    return FlashcardDraft(
                        question: "Explain \(keyword)",
                        answer: line,
                        style: .explanation
                    )
                }
        )
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

    private nonisolated static func bestKeyword(in sentence: String, allowVerbs: Bool) -> String? {
        let tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass])
        tagger.string = sentence

        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        var candidates: [String] = []

        tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .nameTypeOrLexicalClass, options: options) { tag, tokenRange in
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
            .first
    }

    private nonisolated static func isUsefulKeyword(_ token: String) -> Bool {
        let stopWords: Set<String> = [
            "the", "and", "with", "from", "that", "this", "these", "those",
            "have", "has", "had", "into", "their", "there", "which", "what",
            "when", "where", "whose", "your", "about", "because", "through"
        ]

        return !stopWords.contains(token.lowercased())
    }

    private nonisolated static func isReasonablePrompt(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 2
            && trimmed.count <= 50
            && !trimmed.contains("?")
            && !looksLikeFrontMatter(trimmed)
            && !isStructuralHeading(trimmed)
            && lettersRatio(in: trimmed) > 0.55
    }

    private nonisolated static func isLikelyHeading(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        return text.count <= 40
            && words.count <= 5
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

        if loweredQuestion.hasPrefix("how ") {
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

        let numberedPattern = #"^\d+[\.\)]\s+"#
        guard let regex = try? NSRegularExpression(pattern: numberedPattern) else { return nil }
        let range = NSRange(trimmedLine.startIndex..<trimmedLine.endIndex, in: trimmedLine)

        if let match = regex.firstMatch(in: trimmedLine, options: [], range: range),
           let matchRange = Range(match.range, in: trimmedLine) {
            return String(trimmedLine[matchRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
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
        let normalizedInput = text.replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalizedInput
            .components(separatedBy: "\n\n")
            .map { normalizeText($0) }
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

    private nonisolated static func prioritizedChunks(
        from chunks: [RankedStudyChunk],
        maximumCount: Int,
        maximumCharacters: Int
    ) -> [RankedStudyChunk] {
        let sortedChunks = chunks.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.orderIndex < rhs.orderIndex
            }
            return lhs.score > rhs.score
        }

        var selected: [RankedStudyChunk] = []
        var totalCharacters = 0

        for chunk in sortedChunks {
            guard selected.count < maximumCount else { break }

            if !selected.isEmpty && totalCharacters + chunk.text.count > maximumCharacters {
                continue
            }

            selected.append(chunk)
            totalCharacters += chunk.text.count
        }

        return selected.sorted { $0.orderIndex < $1.orderIndex }
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

        let studyMarkers = [
            " is ", " are ", " refers to ", " means ", " because ", " therefore ",
            " used to ", " causes ", " compared", " unlike ", " first ", " next ", " finally "
        ]

        for marker in studyMarkers where loweredText.contains(marker) {
            score += 6
        }

        if lines.count >= 2 {
            score += min(lines.count * 2, 12)
        }

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

        return score
    }

    private nonisolated static func isStudyQuestion(_ question: String) -> Bool {
        let loweredQuestion = question.lowercased()
        let acceptedPrefixes = ["what ", "how ", "why ", "explain ", "compare "]

        return question.count >= 8
            && question.count <= 140
            && !looksLikeFrontMatter(question)
            && !loweredQuestion.contains("cover page")
            && !loweredQuestion.contains("table of contents")
            && acceptedPrefixes.contains(where: { loweredQuestion.hasPrefix($0) })
    }

    private nonisolated static func isStudyAnswer(_ answer: String) -> Bool {
        answer.count >= 10
            && answer.count <= 420
            && !looksLikeFrontMatter(answer)
            && lettersRatio(in: answer) > 0.5
    }

    private nonisolated static func isStudyLine(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLine.count >= 4 else { return false }
        guard lettersRatio(in: trimmedLine) > 0.35 else { return false }
        guard !looksLikeFrontMatter(trimmedLine) else { return false }

        if trimmedLine.range(of: #"^page\s+\d+$"#, options: .regularExpression) != nil {
            return false
        }

        if trimmedLine.range(of: #"^\d+$"#, options: .regularExpression) != nil {
            return false
        }

        return true
    }

    private nonisolated static func looksLikeFrontMatter(_ text: String) -> Bool {
        let loweredText = text.lowercased()
        let frontMatterKeywords = [
            "table of contents", "contents", "student name", "student number", "module code",
            "module title", "course code", "assignment", "submitted by", "prepared by",
            "all rights reserved", "copyright", "acknowledgements", "bibliography",
            "references", "appendix", "lecturer", "university", "department"
        ]

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

        return blockedHeadings.contains(loweredText)
    }

    private nonisolated static func lettersRatio(in text: String) -> Double {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return 0 }

        let letters = trimmedText.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let significantCharacters = trimmedText.unicodeScalars.filter { !$0.properties.isWhitespace }.count
        guard significantCharacters > 0 else { return 0 }

        return Double(letters) / Double(significantCharacters)
    }

    private nonisolated static func normalizeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
