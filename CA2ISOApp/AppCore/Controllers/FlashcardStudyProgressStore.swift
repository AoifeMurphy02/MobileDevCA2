//
//  FlashcardStudyProgressStore.swift
//  CA2ISOApp
//
//  Created by Meghana on 03/05/2026.
//

import Foundation

struct FlashcardStudyProgressSnapshot: Codable, Hashable {
    let deckID: String
    let deckTitle: String
    let studySubject: String
    let totalCardCount: Int
    let reviewedCardCount: Int
    let learnedCardCount: Int
    let stillLearningCardCount: Int
    let lastStudiedAt: Date

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
            studySubject: flashcardSet.studySubject,
            totalCardCount: flashcardSet.cards.count,
            reviewedCardCount: 0,
            learnedCardCount: 0,
            stillLearningCardCount: 0,
            lastStudiedAt: flashcardSet.createdAt
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
        stillLearningCardCount: Int
    ) {
        let deckID = deckID(for: flashcardSet)
        var snapshots = loadAllSnapshots()

        let snapshot = FlashcardStudyProgressSnapshot(
            deckID: deckID,
            deckTitle: flashcardSet.title,
            studySubject: flashcardSet.studySubject,
            totalCardCount: flashcardSet.cards.count,
            reviewedCardCount: max(reviewedCardCount, 0),
            learnedCardCount: max(learnedCardCount, 0),
            stillLearningCardCount: max(stillLearningCardCount, 0),
            lastStudiedAt: .now
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
        } catch {
            print("Could not save flashcard study progress: \(error.localizedDescription)")
        }
    }
}
