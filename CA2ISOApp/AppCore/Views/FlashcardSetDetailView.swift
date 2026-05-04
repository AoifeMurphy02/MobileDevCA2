//
//  FlashcardSetDetailView.swift
//  CA2ISOApp
//
//  Created by Meghana on 17/04/2026.
//

import SwiftData
import SwiftUI

private enum FlashcardStudyRound {
    case all
    case reviewOnly
    case starredOnly

    var title: String {
        switch self {
        case .all:
            return "Full Deck"
        case .reviewOnly:
            return "Still Learning"
        case .starredOnly:
            return "Starred Cards"
        }
    }
}

struct FlashcardSetDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    
    @Environment(AppViewModel.self) private var viewModel
    @Query var allUsers: [User]

    let flashcardSet: FlashcardSet

    @State private var activeRound: FlashcardStudyRound = .all
    @State private var studyCardIDs: [PersistentIdentifier] = []
    @State private var currentIndex = 0
    @State private var showAnswer = false
    @State private var cardRotation = 0.0
    @State private var sessionComplete = false
    @State private var masteredCardIDs: Set<PersistentIdentifier> = []
    @State private var reviewCardIDs: Set<PersistentIdentifier> = []
    @State private var showAssistantSheet = false

    private var orderedCards: [Flashcard] {
        flashcardSet.cards.sorted(by: { $0.orderIndex < $1.orderIndex })
    }

    private var activeCards: [Flashcard] {
        let cardLookup = Dictionary(uniqueKeysWithValues: orderedCards.map { ($0.persistentModelID, $0) })
        let resolvedIDs = studyCardIDs.isEmpty ? orderedCards.map(\.persistentModelID) : studyCardIDs
        return resolvedIDs.compactMap { cardLookup[$0] }
    }

    private var starredCardIDs: [PersistentIdentifier] {
        orderedCards
            .filter(\.isStarred)
            .map(\.persistentModelID)
    }

    private var currentCard: Flashcard? {
        guard activeCards.indices.contains(currentIndex) else { return nil }
        return activeCards[currentIndex]
    }

    private var notificationDeckID: String {
        "\(flashcardSet.title)-\(Int(flashcardSet.createdAt.timeIntervalSince1970))"
    }

    private var hasMeaningfulProgress: Bool {
        !sessionComplete && (
            currentIndex > 0 ||
            showAnswer ||
            !masteredCardIDs.isEmpty ||
            !reviewCardIDs.isEmpty
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if sessionComplete {
                FlashcardSessionCompleteView(
                    title: flashcardSet.title,
                    roundTitle: activeRound.title,
                    masteredCount: masteredCardIDs.count,
                    reviewCount: reviewCardIDs.count,
                    totalCount: activeCards.count,
                    restartLabel: activeRound == .all ? "Study Again" : "Restart Round",
                    restartAction: {
                        startRound(activeRound, resetProgress: activeRound == .all)
                    },
                    reviewAction: reviewCardIDs.isEmpty || activeRound == .reviewOnly ? nil : {
                        startRound(.reviewOnly)
                    },
                    starredAction: starredCardIDs.isEmpty || activeRound == .starredOnly ? nil : {
                        startRound(.starredOnly)
                    }
                )
                .padding(24)
            } else if let currentCard {
                VStack(spacing: 18) {
                    header(for: currentCard)
                    statusDots

                    Spacer()

                    FlashcardStudyCard(
                        question: currentCard.question,
                        answer: currentCard.answer,
                        showAnswer: showAnswer,
                        rotation: cardRotation,
                        isStarred: currentCard.isStarred
                    )
                    .padding(.horizontal, 36)
                    .onTapGesture {
                        revealAnswer()
                    }
                    .gesture(
                        DragGesture(minimumDistance: 40)
                            .onEnded { value in
                                guard showAnswer else { return }

                                if value.translation.width < -60 {
                                    markStillLearning()
                                } else if value.translation.width > 60 {
                                    markMastered()
                                }
                            }
                    )

                    Text(showAnswer ? "Swipe left for still learning or right for got it" : "Tap the card to reveal the answer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)

                    if showAnswer {
                        HStack(spacing: 14) {
                            Button {
                                markStillLearning()
                            } label: {
                                StudyActionButtonLabel(
                                    title: "Still Learning",
                                    tint: Color(red: 0.98, green: 0.48, blue: 0.43)
                                )
                            }

                            Button {
                                markMastered()
                            } label: {
                                StudyActionButtonLabel(
                                    title: "Got It",
                                    tint: Color(red: 0.45, green: 0.81, blue: 0.49)
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 10)

                        FlashcardCardInsightPanel(card: currentCard)
                            .padding(.horizontal, 24)
                            .padding(.top, 4)
                    } else {
                        Button {
                            revealAnswer()
                        } label: {
                            Text("Reveal Answer")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color(red: 0.25, green: 0.53, blue: 0.94))
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 36)
                        .padding(.top, 10)
                    }

                    Spacer()

                    FlashcardStudySummary(
                        title: flashcardSet.title,
                        studyArea: flashcardSet.studyArea,
                        sourceType: flashcardSet.sourceType,
                        aiGenerationMode: flashcardSet.aiGenerationMode,
                        aiModelID: flashcardSet.aiModelID,
                        masteredCount: masteredCardIDs.count,
                        reviewCount: reviewCardIDs.count
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
            } else {
                ContentUnavailableView(
                    "No Flashcards Available",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Create or import a flashcard set first.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .enableSwipeBack()
        .onAppear {
            StudyNotificationManager.cancelResumeStudy(for: notificationDeckID)
            StudyNotificationManager.cancelReviewReminder(for: notificationDeckID)
            guard studyCardIDs.isEmpty else { return }
            startRound(.all, resetProgress: true)
        }
        .onDisappear {
            scheduleResumeReminderIfNeeded()
        }
        .onChange(of: scenePhase) { _, newValue in
            switch newValue {
            case .active:
                StudyNotificationManager.cancelResumeStudy(for: notificationDeckID)
            case .background:
                scheduleResumeReminderIfNeeded()
            default:
                break
            }
        }
        .sheet(isPresented: $showAssistantSheet) {
            FlashcardDeckAssistantView(flashcardSet: flashcardSet)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAssistantSheet = true
                } label: {
                    Image(systemName: "sparkles.rectangle.stack")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    FlashcardStudyProgressStore.removeProgress(for: flashcardSet)
                    modelContext.delete(flashcardSet)
                    try? modelContext.save()
                    dismiss()
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func header(for card: Flashcard) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "arrow.left")
                    .font(.headline)
                    .foregroundColor(Color(red: 0.43, green: 0.63, blue: 0.98))
            }

            Spacer()

            Text("\(currentIndex + 1)/\(activeCards.count)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.43, green: 0.63, blue: 0.98))

            Spacer()

            Button {
                toggleStar(for: card)
            } label: {
                Image(systemName: card.isStarred ? "star.fill" : "star")
                    .font(.headline)
                    .foregroundColor(Color(red: 0.23, green: 0.26, blue: 0.74))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private var statusDots: some View {
        HStack {
            Circle()
                .fill(Color(red: 0.98, green: 0.48, blue: 0.43))
                .frame(width: 26, height: 26)

            Spacer()

            Circle()
                .fill(Color(red: 0.45, green: 0.81, blue: 0.49))
                .frame(width: 26, height: 26)
        }
        .padding(.horizontal, 36)
        .padding(.top, 8)
    }

    private func revealAnswer() {
        guard !showAnswer else { return }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            showAnswer = true
            cardRotation = 180
        }
    }

    private func markStillLearning() {
        guard let currentCard else { return }
        reviewCardIDs.insert(currentCard.persistentModelID)
        masteredCardIDs.remove(currentCard.persistentModelID)
        persistProgressSnapshot()
        recordStudyActivity()
        moveToNextCard()
    }

    private func markMastered() {
        guard let currentCard else { return }
        masteredCardIDs.insert(currentCard.persistentModelID)
        reviewCardIDs.remove(currentCard.persistentModelID)
        persistProgressSnapshot()
        recordStudyActivity()
        moveToNextCard()
    }

    private func moveToNextCard() {
        if currentIndex < activeCards.count - 1 {
            currentIndex += 1
            withAnimation(.easeInOut(duration: 0.2)) {
                showAnswer = false
                cardRotation = 0
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                sessionComplete = true
                
            }
            print("DEBUG: Deck finished! Updating streak...")
                    viewModel.recordStudyActivity(modelContext: modelContext, users: allUsers)
            finishSession()
        }
    }

    private func toggleStar(for card: Flashcard) {
        card.isStarred.toggle()
        try? modelContext.save()
    }

    private func startRound(_ round: FlashcardStudyRound, resetProgress: Bool = false) {
        activeRound = round
        studyCardIDs = cardIDs(for: round)
        currentIndex = 0
        showAnswer = false
        cardRotation = 0
        sessionComplete = false
        StudyNotificationManager.cancelResumeStudy(for: notificationDeckID)

        if round == .reviewOnly {
            StudyNotificationManager.cancelReviewReminder(for: notificationDeckID)
        }

        if resetProgress {
            masteredCardIDs.removeAll()
            reviewCardIDs.removeAll()
            StudyNotificationManager.cancelReviewReminder(for: notificationDeckID)
        }
    }

    private func cardIDs(for round: FlashcardStudyRound) -> [PersistentIdentifier] {
        switch round {
        case .all:
            return orderedCards.map(\.persistentModelID)
        case .reviewOnly:
            return orderedCards
                .filter { reviewCardIDs.contains($0.persistentModelID) }
                .map(\.persistentModelID)
        case .starredOnly:
            return starredCardIDs
        }
    }

    private func recordStudyActivity() {
        StudyNotificationManager.recordStudyActivity(
            deckTitle: flashcardSet.title,
            studyArea: flashcardSet.studyArea
        )
    }

    private func finishSession() {
        StudyNotificationManager.cancelResumeStudy(for: notificationDeckID)
        persistProgressSnapshot()
        recordStudyActivity()

        if reviewCardIDs.isEmpty {
            StudyNotificationManager.cancelReviewReminder(for: notificationDeckID)
            return
        }

        StudyNotificationManager.scheduleReviewReminder(
            deckID: notificationDeckID,
            deckTitle: flashcardSet.title,
            reviewCount: reviewCardIDs.count
        )
    }

    private func scheduleResumeReminderIfNeeded() {
        guard hasMeaningfulProgress, !activeCards.isEmpty else {
            StudyNotificationManager.cancelResumeStudy(for: notificationDeckID)
            return
        }

        let currentCardNumber = min(currentIndex + 1, activeCards.count)
        let progressText = "You were on card \(currentCardNumber) of \(activeCards.count) in \(flashcardSet.title). Pick it up where you left off."

        StudyNotificationManager.scheduleResumeStudy(
            deckID: notificationDeckID,
            deckTitle: flashcardSet.title,
            studyArea: flashcardSet.studyArea,
            progressText: progressText
        )
    }

    private func persistProgressSnapshot() {
        let learnedCount = masteredCardIDs.count
        let stillLearningCount = reviewCardIDs.count

        FlashcardStudyProgressStore.updateProgress(
            for: flashcardSet,
            reviewedCardCount: learnedCount + stillLearningCount,
            learnedCardCount: learnedCount,
            stillLearningCardCount: stillLearningCount
        )
    }
}

private struct FlashcardStudyCard: View {
    let question: String
    let answer: String
    let showAnswer: Bool
    let rotation: Double
    let isStarred: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(showAnswer ? Color(red: 0.86, green: 0.92, blue: 1.0) : Color(red: 0.47, green: 0.67, blue: 0.95))
                .shadow(color: .black.opacity(0.08), radius: 18, y: 10)

            VStack(spacing: 18) {
                Spacer()

                Text(showAnswer ? answer : question)
                    .font(.system(size: showAnswer ? 30 : 32, weight: .bold, design: .rounded))
                    .foregroundColor(showAnswer ? .black : .white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .rotation3DEffect(
                        .degrees(showAnswer ? 180 : 0),
                        axis: (x: 0, y: 1, z: 0)
                    )

                Spacer()
            }
            .padding(.vertical, 28)
        }
        .frame(height: 420)
        .rotation3DEffect(
            .degrees(rotation),
            axis: (x: 0, y: 1, z: 0)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: isStarred ? "star.fill" : "star")
                .foregroundColor(showAnswer ? Color(red: 0.23, green: 0.26, blue: 0.74) : .white.opacity(0.9))
                .padding(20)
        }
    }
}

private struct StudyActionButtonLabel: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.7), lineWidth: 1.5)
            )
    }
}

private struct FlashcardStudySummary: View {
    let title: String
    let studyArea: String
    let sourceType: String
    let aiGenerationMode: String
    let aiModelID: String
    let masteredCount: Int
    let reviewCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.black)

            Text(summaryLine)
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                SummaryPill(title: "\(masteredCount) got it", tint: Color(red: 0.45, green: 0.81, blue: 0.49))
                SummaryPill(title: "\(reviewCount) review", tint: Color(red: 0.98, green: 0.48, blue: 0.43))
            }

            if !aiGenerationMode.isEmpty || !aiModelID.isEmpty {
                HStack(spacing: 12) {
                    if !aiGenerationMode.isEmpty {
                        SummaryPill(
                            title: FlashcardAISettingsStore.title(forGenerationMode: aiGenerationMode),
                            tint: Color(red: 0.87, green: 0.49, blue: 0.16)
                        )
                    }

                    if !aiModelID.isEmpty {
                        SummaryPill(
                            title: aiModelID,
                            tint: Color(red: 0.41, green: 0.37, blue: 0.86)
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryLine: String {
        [studyArea, sourceType]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}

private struct FlashcardCardInsightPanel: View {
    let card: Flashcard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SummaryPill(title: card.confidence.title, tint: confidenceTint)

                if !card.evidenceExcerpt.isEmpty {
                    SummaryPill(title: "Grounded in source", tint: Color(red: 0.25, green: 0.53, blue: 0.94))
                }
            }

            if !card.evidenceExcerpt.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Why this answer")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    Text(card.evidenceExcerpt)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.98, green: 0.99, blue: 1.0))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var confidenceTint: Color {
        switch card.confidence {
        case .high:
            return Color(red: 0.18, green: 0.63, blue: 0.35)
        case .medium:
            return Color(red: 0.91, green: 0.57, blue: 0.13)
        case .low:
            return Color(red: 0.86, green: 0.27, blue: 0.24)
        }
    }
}

private struct SummaryPill: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct FlashcardSessionCompleteView: View {
    let title: String
    let roundTitle: String
    let masteredCount: Int
    let reviewCount: Int
    let totalCount: Int
    let restartLabel: String
    let restartAction: () -> Void
    let reviewAction: (() -> Void)?
    let starredAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundColor(Color(red: 0.25, green: 0.53, blue: 0.94))

            Text("Session Complete")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.25, green: 0.53, blue: 0.94))

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(roundTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                SummaryPill(title: "\(masteredCount) got it", tint: Color(red: 0.45, green: 0.81, blue: 0.49))
                SummaryPill(title: "\(reviewCount) review", tint: Color(red: 0.98, green: 0.48, blue: 0.43))
            }

            Text("You reviewed \(totalCount) cards in this round.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(action: restartAction) {
                Text(restartLabel)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.25, green: 0.53, blue: 0.94))
                    .clipShape(Capsule())
            }

            if let reviewAction {
                Button(action: reviewAction) {
                    Text("Review Missed Cards")
                        .font(.headline)
                        .foregroundColor(Color(red: 0.98, green: 0.48, blue: 0.43))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .overlay(
                            Capsule()
                                .stroke(Color(red: 0.98, green: 0.48, blue: 0.43).opacity(0.5), lineWidth: 1.4)
                        )
                }
            }

            if let starredAction {
                Button(action: starredAction) {
                    Text("Study Starred Cards")
                        .font(.headline)
                        .foregroundColor(Color(red: 0.23, green: 0.26, blue: 0.74))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .overlay(
                            Capsule()
                                .stroke(Color(red: 0.23, green: 0.26, blue: 0.74).opacity(0.35), lineWidth: 1.4)
                        )
                }
            }

            Spacer()
        }
    }
}
