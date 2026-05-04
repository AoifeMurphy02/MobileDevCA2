//
//  FlashcardModels.swift
//  CA2ISOApp
//
//  Created by Meghana on 17/04/2026.
//

import Foundation
import SwiftData

enum FlashcardConfidence: String, CaseIterable, Hashable, Codable, Sendable {
    case low
    case medium
    case high

    nonisolated var title: String {
        switch self {
        case .low:
            return "Low Confidence"
        case .medium:
            return "Medium Confidence"
        case .high:
            return "High Confidence"
        }
    }

    nonisolated var shortTitle: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }

    nonisolated var rank: Int {
        switch self {
        case .low:
            return 1
        case .medium:
            return 2
        case .high:
            return 3
        }
    }
}

@Model
final class FlashcardSet {
    var title: String = ""
    var ownerEmail: String = ""
    var sourceType: String = ""
    var studyArea: String = ""
    var topic: String = ""
    var rawText: String = ""
    var aiGenerationMode: String = ""
    var aiModelID: String = ""
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Flashcard.parentSet)
    var cards: [Flashcard] = []

    init(
        title: String,
        ownerEmail: String = "",
        sourceType: String,
        studyArea: String = "",
        topic: String = "",
        rawText: String,
        aiGenerationMode: String = "",
        aiModelID: String = "",
        createdAt: Date = .now
    ) {
        self.title = title
        self.ownerEmail = ownerEmail
        self.sourceType = sourceType
        self.studyArea = studyArea
        self.topic = topic
        self.rawText = rawText
        self.aiGenerationMode = aiGenerationMode
        self.aiModelID = aiModelID
        self.createdAt = createdAt
       
    }
}

@Model
final class Flashcard {
    var question: String = ""
    var answer: String = ""
    var confidenceRawValue: String = FlashcardConfidence.medium.rawValue
    var evidenceExcerpt: String = ""
    var orderIndex: Int = 0
    var isStarred: Bool = false
    var parentSet: FlashcardSet?

    var confidence: FlashcardConfidence {
        get { FlashcardConfidence(rawValue: confidenceRawValue) ?? .medium }
        set { confidenceRawValue = newValue.rawValue }
    }

    init(
        question: String,
        answer: String,
        confidenceRawValue: String = FlashcardConfidence.medium.rawValue,
        evidenceExcerpt: String = "",
        orderIndex: Int,
        isStarred: Bool = false,
        parentSet: FlashcardSet? = nil
    ) {
        self.question = question
        self.answer = answer
        self.confidenceRawValue = confidenceRawValue
        self.evidenceExcerpt = evidenceExcerpt
        self.orderIndex = orderIndex
        self.isStarred = isStarred
        self.parentSet = parentSet
    }
}

enum FlashcardPromptStyle: String, CaseIterable, Hashable, Codable, Sendable {
    case definition
    case explanation
    case why
    case how
    case compare
    case summary

    nonisolated var title: String {
        switch self {
        case .definition:
            return "Definition"
        case .explanation:
            return "Explain"
        case .why:
            return "Why"
        case .how:
            return "How"
        case .compare:
            return "Compare"
        case .summary:
            return "Key Idea"
        }
    }

    nonisolated var iconName: String {
        switch self {
        case .definition:
            return "text.book.closed"
        case .explanation:
            return "lightbulb"
        case .why:
            return "questionmark.circle"
        case .how:
            return "gearshape.2"
        case .compare:
            return "arrow.left.arrow.right"
        case .summary:
            return "sparkles"
        }
    }
}

struct FlashcardDraft: Sendable {
    let id: UUID
    var question: String
    var answer: String
    var style: FlashcardPromptStyle
    var confidence: FlashcardConfidence
    var evidenceExcerpt: String

    nonisolated init(
        id: UUID = UUID(),
        question: String,
        answer: String,
        style: FlashcardPromptStyle = .summary,
        confidence: FlashcardConfidence = .medium,
        evidenceExcerpt: String = ""
    ) {
        self.id = id
        self.question = question
        self.answer = answer
        self.style = style
        self.confidence = confidence
        self.evidenceExcerpt = evidenceExcerpt
    }
}

extension FlashcardDraft: Identifiable, Hashable { }

struct FlashcardDeckDraft: Sendable {
    var title: String
    var sourceType: String
    var studyArea: String
    var topic: String
    var rawText: String
    var aiGenerationMode: String
    var aiModelID: String
    var cards: [FlashcardDraft]

    nonisolated init(
        title: String,
        sourceType: String,
        studyArea: String,
        topic: String,
        rawText: String,
        aiGenerationMode: String = "",
        aiModelID: String = "",
        cards: [FlashcardDraft]
    ) {
        self.title = title
        self.sourceType = sourceType
        self.studyArea = studyArea
        self.topic = topic
        self.rawText = rawText
        self.aiGenerationMode = aiGenerationMode
        self.aiModelID = aiModelID
        self.cards = cards
    }
}

enum FlashcardSetVisibility {
    nonisolated static func visibleSets(
        _ sets: [FlashcardSet],
        currentUserEmail: String?,
        totalUserCount: Int,
        activeStudyArea: String = ""
    ) -> [FlashcardSet] {
        let normalizedCurrentUserEmail = normalize(currentUserEmail)
        guard !normalizedCurrentUserEmail.isEmpty else {
            return []
        }

        let ownedSets = sets.filter { normalize($0.ownerEmail) == normalizedCurrentUserEmail }
        let legacySets = totalUserCount <= 1
            ? sets.filter { normalize($0.ownerEmail).isEmpty }
            : []

        let ownedSetIDs = Set(ownedSets.map(\.persistentModelID))
        let combinedSets = ownedSets + legacySets.filter { !ownedSetIDs.contains($0.persistentModelID) }

        guard !activeStudyArea.isEmpty else {
            return combinedSets
        }

        return combinedSets.filter { $0.studyArea == activeStudyArea }
    }

    private nonisolated static func normalize(_ email: String?) -> String {
        (email ?? "")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
