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

    var title: String {
        switch self {
        case .all:
            return "Full Deck"
        case .reviewOnly:
            return "Still Learning"
        }
    }
}

struct FlashcardSetDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    
    @Environment(AppViewModel.self) private var viewModel

    let flashcardSet: FlashcardSet
    let shouldResumeProgress: Bool

    init(flashcardSet: FlashcardSet, shouldResumeProgress: Bool = false) {
        self.flashcardSet = flashcardSet
        self.shouldResumeProgress = shouldResumeProgress
    }

    @State private var activeRound: FlashcardStudyRound = .all
    @State private var studyCardIDs: [PersistentIdentifier] = []
    @State private var currentIndex = 0
    @State private var showAnswer = false
    @State private var cardRotation = 0.0
    @State private var dragOffset: CGSize = .zero
    @State private var isCardExpanded = false
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
                    finishAction: {
                        dismiss()
                        viewModel.goHome()
                    }
                    
                )
                .padding(24)
            } else if let currentCard {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        header
                        statusDots

                        FlashcardStudyCard(
                            question: currentCard.question,
                            answer: currentCard.answer,
                            showAnswer: showAnswer,
                            rotation: cardRotation,
                            dragOffset: dragOffset,
                            isExpanded: isCardExpanded,
                            toggleExpanded: {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    isCardExpanded.toggle()
                                }
                            }
                        )
                        .padding(.horizontal, 28)
                        .padding(.top, 14)
                        .onTapGesture {
                            revealAnswer()
                        }
                        .highPriorityGesture(cardSwipeGesture)

                        SwipeInstructionView(showAnswer: showAnswer)
                            .padding(.horizontal, 28)
                            .padding(.top, 4)

                        if showAnswer {
                            HStack(spacing: 14) {
                                Button {
                                    animateCardAway(toRight: false)
                                } label: {
                                    StudyActionButtonLabel(
                                        title: "Still Learning",
                                        tint: Color(red: 0.98, green: 0.48, blue: 0.43)
                                    )
                                }

                                Button {
                                    animateCardAway(toRight: true)
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
                        .padding(.bottom, 28)
                    }
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
        .background(AppTheme.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .enableSwipeBack()
        .onAppear {
            StudyNotificationManager.cancelResumeStudy(for: notificationDeckID)
            StudyNotificationManager.cancelReviewReminder(for: notificationDeckID)
            guard studyCardIDs.isEmpty else { return }
            if shouldResumeProgress {
                restoreSavedProgressOrStartFresh()
            } else {
                startRound(.all, resetProgress: false)
            }
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

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundColor(AppTheme.primary)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.surface)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(AppTheme.subtleBorder, lineWidth: 1)
                    )
            }

            Spacer()

            Text("\(currentIndex + 1)/\(activeCards.count)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.43, green: 0.63, blue: 0.98))

            Spacer()

            Image(systemName: "rectangle.stack.fill")
                .font(.headline)
                .foregroundColor(Color(red: 0.43, green: 0.63, blue: 0.98))
                .frame(width: 42, height: 42)
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

    private var cardSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard showAnswer else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard showAnswer else {
                    resetCardMotion()
                    return
                }

                let swipeWidth = value.predictedEndTranslation.width
                if swipeWidth < -95 {
                    animateCardAway(toRight: false)
                } else if swipeWidth > 95 {
                    animateCardAway(toRight: true)
                } else {
                    resetCardMotion()
                }
            }
    }

    private func animateCardAway(toRight: Bool) {
        let exitX: CGFloat = toRight ? 900 : -900
        let exitY = dragOffset.height

        withAnimation(.easeIn(duration: 0.22)) {
            dragOffset = CGSize(width: exitX, height: exitY)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if toRight {
                markMastered()
            } else {
                markStillLearning()
            }
        }
    }

    private func resetCardMotion() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            dragOffset = .zero
        }
    }

    private func markStillLearning() {
        guard let currentCard else { return }
        reviewCardIDs.insert(currentCard.persistentModelID)
        masteredCardIDs.remove(currentCard.persistentModelID)
        persistProgressSnapshot(currentCardIndex: nextCardIndexAfterCurrent)
        recordStudyActivity()
        moveToNextCard()
    }

    private func markMastered() {
        guard let currentCard else { return }
        masteredCardIDs.insert(currentCard.persistentModelID)
        reviewCardIDs.remove(currentCard.persistentModelID)
        persistProgressSnapshot(currentCardIndex: nextCardIndexAfterCurrent)
        recordStudyActivity()
        moveToNextCard()
    }

    private var nextCardIndexAfterCurrent: Int {
        min(currentIndex + 1, max(activeCards.count - 1, 0))
    }

    private func moveToNextCard() {
        dragOffset = .zero
        isCardExpanded = false

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
                    viewModel.recordStudyActivity(modelContext: modelContext)
            finishSession()
        }
    }

    private func startRound(_ round: FlashcardStudyRound, resetProgress: Bool = false) {
        activeRound = round
        studyCardIDs = cardIDs(for: round)
        currentIndex = 0
        showAnswer = false
        cardRotation = 0
        dragOffset = .zero
        isCardExpanded = false
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
        }
    }

    private func restoreSavedProgressOrStartFresh() {
        let snapshot = FlashcardStudyProgressStore.snapshot(for: flashcardSet)
        studyCardIDs = cardIDs(for: .all)
        masteredCardIDs = cardIDs(from: snapshot.learnedCardIndexes)
        reviewCardIDs = cardIDs(from: snapshot.stillLearningCardIndexes)

        if snapshot.reviewedCardCount >= activeCards.count, !activeCards.isEmpty {
            currentIndex = max(activeCards.count - 1, 0)
            sessionComplete = true
        } else {
            currentIndex = min(max(snapshot.currentCardIndex ?? 0, 0), max(activeCards.count - 1, 0))
            sessionComplete = false
        }

        activeRound = .all
        showAnswer = false
        cardRotation = 0
        dragOffset = .zero
        isCardExpanded = false
    }

    private func cardIDs(from orderIndexes: [Int]?) -> Set<PersistentIdentifier> {
        let requestedIndexes = Set(orderIndexes ?? [])
        return Set(
            orderedCards
                .filter { requestedIndexes.contains($0.orderIndex) }
                .map(\.persistentModelID)
        )
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

    private func persistProgressSnapshot(currentCardIndex savedCurrentCardIndex: Int? = nil) {
        let learnedCount = masteredCardIDs.count
        let stillLearningCount = reviewCardIDs.count

        FlashcardStudyProgressStore.updateProgress(
            for: flashcardSet,
            reviewedCardCount: learnedCount + stillLearningCount,
            learnedCardCount: learnedCount,
            stillLearningCardCount: stillLearningCount,
            currentCardIndex: savedCurrentCardIndex ?? currentIndex,
            learnedCardIndexes: orderIndexes(for: masteredCardIDs),
            stillLearningCardIndexes: orderIndexes(for: reviewCardIDs)
        )
    }

    private func orderIndexes(for cardIDs: Set<PersistentIdentifier>) -> [Int] {
        orderedCards
            .filter { cardIDs.contains($0.persistentModelID) }
            .map(\.orderIndex)
            .sorted()
    }
}

private struct FlashcardStudyCard: View {
    let question: String
    let answer: String
    let showAnswer: Bool
    let rotation: Double
    let dragOffset: CGSize
    let isExpanded: Bool
    let toggleExpanded: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(baseCardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(swipeTint.opacity(swipeOpacity))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(borderColor, lineWidth: showAnswer ? 1.4 : 1.1)
                )
                .shadow(color: swipeTint.opacity(swipeOpacity * 0.45), radius: 28, y: 14)
                .shadow(color: .black.opacity(0.12), radius: 18, y: 10)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(showAnswer ? "Answer" : "Question", systemImage: showAnswer ? "checkmark.message.fill" : "questionmark.bubble.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(showAnswer ? AppTheme.primary : .white.opacity(0.92))

                    Spacer()

                    if shouldShowExpandButton {
                        Button(action: toggleExpanded) {
                            Label(isExpanded ? "Collapse" : "Expand", systemImage: isExpanded ? "chevron.up" : "arrow.up.left.and.arrow.down.right")
                                .font(.caption.weight(.bold))
                                .foregroundColor(showAnswer ? AppTheme.primary : .white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background((showAnswer ? AppTheme.primary : Color.white).opacity(showAnswer ? 0.12 : 0.18))
                                .clipShape(Capsule())
                        }
                    }
                }

                if showAnswer {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Answer")
                            .font(.caption.weight(.bold))
                            .foregroundColor(AppTheme.secondaryText)
                            .textCase(.uppercase)

                        Text(answer)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.text)
                            .multilineTextAlignment(.leading)
                            .lineLimit(isExpanded ? nil : 8)
                            .minimumScaleFactor(0.78)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider()
                        .background(AppTheme.subtleBorder)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Question")
                            .font(.caption.weight(.bold))
                            .foregroundColor(AppTheme.secondaryText)
                            .textCase(.uppercase)

                        Text(question)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(AppTheme.secondaryText)
                            .lineLimit(isExpanded ? nil : 3)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text(question)
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(isExpanded ? nil : 8)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 0)

                    Text("Tap to reveal, then swipe the full card.")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(28)

            if showAnswer {
                swipeBadge
            }
        }
        .frame(minHeight: 420, maxHeight: isExpanded ? nil : 420, alignment: .top)
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .offset(dragOffset)
        .rotationEffect(.degrees(Double(dragOffset.width / 14)))
        .scaleEffect(dragOffset == .zero ? 1 : 0.97)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    private var baseCardBackground: Color {
        showAnswer ? AppTheme.surface : Color(red: 0.12, green: 0.35, blue: 0.82)
    }

    private var shouldShowExpandButton: Bool {
        if showAnswer {
            return needsExpansion(answer, characterLimit: 180, lineLimit: 5) ||
                needsExpansion(question, characterLimit: 120, lineLimit: 3)
        }

        return needsExpansion(question, characterLimit: 180, lineLimit: 6)
    }

    private func needsExpansion(_ text: String, characterLimit: Int, lineLimit: Int) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitLineCount = trimmedText
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
        let estimatedWrappedLineCount = Int(ceil(Double(trimmedText.count) / 34.0))

        return trimmedText.count > characterLimit ||
            explicitLineCount > lineLimit ||
            estimatedWrappedLineCount > lineLimit
    }

    private var borderColor: Color {
        if swipeOpacity > 0.15 { return swipeTint.opacity(0.85) }
        return showAnswer ? AppTheme.subtleBorder : Color.white.opacity(0.25)
    }

    private var swipeTint: Color {
        dragOffset.width >= 0 ? Color(red: 0.18, green: 0.72, blue: 0.36) : Color(red: 0.96, green: 0.26, blue: 0.24)
    }

    private var swipeOpacity: Double {
        min(Double(abs(dragOffset.width) / 150), 1)
    }

    @ViewBuilder
    private var swipeBadge: some View {
        if abs(dragOffset.width) > 28 {
            let isMastered = dragOffset.width > 0
            Text(isMastered ? "Got It" : "Review")
                .font(.headline.weight(.black))
                .foregroundColor(isMastered ? Color.green : Color.red)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .overlay(
                    Capsule()
                        .stroke(isMastered ? Color.green : Color.red, lineWidth: 2)
                )
                .rotationEffect(.degrees(isMastered ? 10 : -10))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isMastered ? .topLeading : .topTrailing)
                .padding(24)
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

private struct SwipeInstructionView: View {
    let showAnswer: Bool

    var body: some View {
        if showAnswer {
            HStack(spacing: 12) {
                SwipeHintPill(icon: "arrow.left", title: "Still learning", tint: Color(red: 0.98, green: 0.48, blue: 0.43))
                SwipeHintPill(icon: "arrow.right", title: "Got it", tint: Color(red: 0.45, green: 0.81, blue: 0.49))
            }
        } else {
            Label("Tap the card to reveal the answer", systemImage: "hand.tap.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppTheme.secondaryText)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct SwipeHintPill: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.bold))
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
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
                .foregroundColor(AppTheme.text)

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
        .background(AppTheme.surface)
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
    let finishAction: () -> Void

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

            Button(action: finishAction) {
                Text("Done")
                    .font(.headline)
                    .foregroundColor(AppTheme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .overlay(
                        Capsule()
                            .stroke(AppTheme.primary.opacity(0.35), lineWidth: 1.4)
                    )
            }

            Spacer()
        }
    }
}
