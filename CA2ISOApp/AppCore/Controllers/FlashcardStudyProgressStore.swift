//
//  FlashcardStudyProgressStore.swift
//  CA2ISOApp
//
//  Created by Meghana on 03/05/2026.
//

import Foundation

extension Notification.Name {
    static let flashcardStudyProgressDidChange = Notification.Name("flashcardStudyProgressDidChange")
}

struct FlashcardStudyProgressSnapshot: Codable, Hashable {
    let deckID: String
    let deckTitle: String
    let studyArea: String
    let totalCardCount: Int
    let reviewedCardCount: Int
    let learnedCardCount: Int
    let stillLearningCardCount: Int
    let lastStudiedAt: Date
    let currentCardIndex: Int?
    let learnedCardIndexes: [Int]?
    let stillLearningCardIndexes: [Int]?

    nonisolated var remainingCardCount: Int {
        max(totalCardCount - reviewedCardCount, 0)
    }

    nonisolated var hasProgress: Bool {
        reviewedCardCount > 0 || learnedCardCount > 0 || stillLearningCardCount > 0
    }

    nonisolated static func empty(for flashcardSet: FlashcardSet) -> FlashcardStudyProgressSnapshot {
        FlashcardStudyProgressSnapshot(
            deckID: FlashcardStudyProgressStore.deckID(for: flashcardSet),
            deckTitle: flashcardSet.title,
            studyArea: flashcardSet.studyArea,
            totalCardCount: flashcardSet.cards.count,
            reviewedCardCount: 0,
            learnedCardCount: 0,
            stillLearningCardCount: 0,
            lastStudiedAt: flashcardSet.createdAt,
            currentCardIndex: nil,
            learnedCardIndexes: nil,
            stillLearningCardIndexes: nil
        )
    }
}

enum FlashcardStudyProgressStore {
    private nonisolated static let progressKey = "flashcard.study.progress.snapshots"

    nonisolated static func deckID(for flashcardSet: FlashcardSet) -> String {
        "\(flashcardSet.title)-\(Int(flashcardSet.createdAt.timeIntervalSince1970))"
    }

    nonisolated static func snapshot(for flashcardSet: FlashcardSet) -> FlashcardStudyProgressSnapshot {
        let deckID = deckID(for: flashcardSet)
        return loadAllSnapshots()[deckID] ?? .empty(for: flashcardSet)
    }

    nonisolated static func loadAllSnapshots() -> [String: FlashcardStudyProgressSnapshot] {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: progressKey) else {
            return [:]
        }

        do {
            return try JSONDecoder().decode([String: FlashcardStudyProgressSnapshot].self, from: data)
        } catch {
            print("Could not decode flashcard study progress: \(error.localizedDescription)")
            return [:]
        }
    }

    nonisolated static func updateProgress(
        for flashcardSet: FlashcardSet,
        reviewedCardCount: Int,
        learnedCardCount: Int,
        stillLearningCardCount: Int,
        currentCardIndex: Int? = nil,
        learnedCardIndexes: [Int]? = nil,
        stillLearningCardIndexes: [Int]? = nil
    ) {
        let deckID = deckID(for: flashcardSet)
        var snapshots = loadAllSnapshots()
        let totalCardCount = flashcardSet.cards.count
        let boundedCurrentIndex = currentCardIndex.map { min(max($0, 0), max(totalCardCount - 1, 0)) }

        let snapshot = FlashcardStudyProgressSnapshot(
            deckID: deckID,
            deckTitle: flashcardSet.title,
            studyArea: flashcardSet.studyArea,
            totalCardCount: totalCardCount,
            reviewedCardCount: max(reviewedCardCount, 0),
            learnedCardCount: max(learnedCardCount, 0),
            stillLearningCardCount: max(stillLearningCardCount, 0),
            lastStudiedAt: .now,
            currentCardIndex: boundedCurrentIndex,
            learnedCardIndexes: learnedCardIndexes,
            stillLearningCardIndexes: stillLearningCardIndexes
        )

        snapshots[deckID] = snapshot
        saveAllSnapshots(snapshots)
    }

    nonisolated static func removeProgress(for flashcardSet: FlashcardSet) {
        let deckID = deckID(for: flashcardSet)
        var snapshots = loadAllSnapshots()
        snapshots.removeValue(forKey: deckID)
        saveAllSnapshots(snapshots)
    }

    private nonisolated static func saveAllSnapshots(_ snapshots: [String: FlashcardStudyProgressSnapshot]) {
        do {
            let data = try JSONEncoder().encode(snapshots)
            UserDefaults.standard.set(data, forKey: progressKey)
            NotificationCenter.default.post(name: .flashcardStudyProgressDidChange, object: nil)
        } catch {
            print("Could not save flashcard study progress: \(error.localizedDescription)")
        }
    }
}
