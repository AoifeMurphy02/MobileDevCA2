//
//  FlashcardModels.swift
//  CA2ISOApp
//
//  Created by Meghana on 17/04/2026.
//

import Foundation
import SwiftData

@Model
final class FlashcardSet {
    var title: String
    var sourceType: String
    var subject: String
    var topic: String
    var rawText: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Flashcard.parentSet)
    var cards: [Flashcard] = []

    init(
        title: String,
        sourceType: String,
        subject: String = "",
        topic: String = "",
        rawText: String,
        createdAt: Date = .now
    ) {
        self.title = title
        self.sourceType = sourceType
        self.subject = subject
        self.topic = topic
        self.rawText = rawText
        self.createdAt = createdAt
    }
}

@Model
final class Flashcard {
    var question: String
    var answer: String
    var orderIndex: Int
    var isStarred: Bool
    var parentSet: FlashcardSet?

    init(
        question: String,
        answer: String,
        orderIndex: Int,
        isStarred: Bool = false,
        parentSet: FlashcardSet? = nil
    ) {
        self.question = question
        self.answer = answer
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

    var title: String {
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

    var iconName: String {
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

    nonisolated init(
        id: UUID = UUID(),
        question: String,
        answer: String,
        style: FlashcardPromptStyle = .summary
    ) {
        self.id = id
        self.question = question
        self.answer = answer
        self.style = style
    }
}

extension FlashcardDraft: Identifiable, Hashable { }

struct FlashcardDeckDraft: Sendable {
    var title: String
    var sourceType: String
    var subject: String
    var topic: String
    var rawText: String
    var cards: [FlashcardDraft]

    nonisolated init(
        title: String,
        sourceType: String,
        subject: String,
        topic: String,
        rawText: String,
        cards: [FlashcardDraft]
    ) {
        self.title = title
        self.sourceType = sourceType
        self.subject = subject
        self.topic = topic
        self.rawText = rawText
        self.cards = cards
    }
}
