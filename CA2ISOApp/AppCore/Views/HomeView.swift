import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \FlashcardSet.createdAt, order: .reverse) private var flashcardSets: [FlashcardSet]
    @State private var progressSnapshots: [String: FlashcardStudyProgressSnapshot] = [:]

    private var visibleSets: [FlashcardSet] {
        guard !viewModel.activeSubject.isEmpty else {
            return flashcardSets
        }

        return flashcardSets.filter { set in
            set.subject == viewModel.activeSubject
        }
    }

    var body: some View {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        headerCard
                        subjectSection
                        
                        // Flashcardsfirst
                        librarySection

                        progressSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 100)
                }

                CustomNavBar(selectedTab: 0)
            }
            .background(Color(red: 0.97, green: 0.99, blue: 1.0).ignoresSafeArea())
            .navigationBarBackButtonHidden(true)
            .onAppear {
                if viewModel.activeSubject.isEmpty, let firstSubject = viewModel.subjectOptions.first {
                    viewModel.selectSubject(firstSubject)
                }

                refreshProgressSnapshots()
            }
            .onChange(of: scenePhase) { _, newValue in
                if newValue == .active {
                    refreshProgressSnapshots()
                }
            }
        }
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome Back")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.82))

                    Text(homeTitle)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Label("\(viewModel.streakCount) day streak", systemImage: "flame.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)

                    Text("\(flashcardSets.count) decks saved")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.78))
                }
            }

            Text(headerDescription)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.88))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.49, blue: 0.95),
                    Color(red: 0.25, green: 0.53, blue: 0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }

    private var subjectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Study Spaces")
                    .font(.headline)

                Spacer()

                Button {
                    viewModel.navPath.append(NavTarget.subjectPicker)
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                }
            }

            if viewModel.subjectOptions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No subjects selected yet.")
                        .font(.headline)
                    Text("Choose subjects to organize your decks and improve AI suggestions.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        SubjectFilterChip(
                            title: "All",
                            isSelected: viewModel.activeSubject.isEmpty
                        ) {
                            viewModel.selectSubject("")
                        }

                        ForEach(viewModel.subjectOptions, id: \.self) { subject in
                            SubjectFilterChip(
                                title: subject,
                                isSelected: viewModel.activeSubject == subject
                            ) {
                                viewModel.selectSubject(subject)
                            }
                        }
                    }
                }
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(progressSectionTitle)
                .font(.headline)

            Text(progressSectionDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if shouldShowDraftProgressCard {
                PendingDraftProgressCard(
                    title: viewModel.flashcardDraftTitle,
                    subject: viewModel.flashcardDraftSubject,
                    cardCount: viewModel.flashcardDraftCards.count
                ) {
                    viewModel.navPath.append(NavTarget.flashcardReview)
                }
            }

            if visibleSets.isEmpty {
                if !shouldShowDraftProgressCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No saved deck progress yet.")
                            .font(.headline)
                        Text("Once you start studying a saved deck, reviewed and learnt card counts will appear here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            } else {
                ForEach(visibleSets.prefix(6)) { flashcardSet in
                    NavigationLink(destination: FlashcardSetDetailView(flashcardSet: flashcardSet)) {
                        DeckProgressCard(
                            flashcardSet: flashcardSet,
                            snapshot: progressSnapshot(for: flashcardSet)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.activeSubject.isEmpty ? "Recent Decks" : "\(viewModel.activeSubject) Decks")
                .font(.headline)

            if visibleSets.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(emptyLibraryTitle)
                        .font(.headline)
                    Text(emptyLibraryDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                ForEach(visibleSets.prefix(8)) { flashcardSet in
                    NavigationLink(destination: FlashcardSetDetailView(flashcardSet: flashcardSet)) {
                        FlashcardSetCard(flashcardSet: flashcardSet)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var homeTitle: String {
        if let currentUserEmail = viewModel.currentUserEmail, !currentUserEmail.isEmpty {
            return currentUserEmail.components(separatedBy: "@").first ?? currentUserEmail
        }

        return "Your Study Hub"
    }

    private var headerDescription: String {
        if viewModel.activeSubject.isEmpty {
            return "See your recent decks, jump into smart flashcard creation, and keep your study routine moving."
        }

        return "You are currently focused on \(viewModel.activeSubject). Create, review, and study decks organized under this subject."
    }

    private var emptyLibraryTitle: String {
        if viewModel.activeSubject.isEmpty {
            return "You have not created any decks yet."
        }

        return "No decks saved for \(viewModel.activeSubject) yet."
    }

    private var emptyLibraryDescription: String {
        if viewModel.activeSubject.isEmpty {
            return "Start with AI flashcards to turn your notes into a study deck."
        }

        return "Create a new deck and it will appear here once you save it."
    }

    private var shouldShowDraftProgressCard: Bool {
        guard viewModel.hasFlashcardDraft else { return false }

        if viewModel.activeSubject.isEmpty {
            return true
        }

        let draftSubject = viewModel.flashcardDraftSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        return draftSubject.isEmpty || draftSubject == viewModel.activeSubject
    }

    private var progressSectionTitle: String {
        if viewModel.activeSubject.isEmpty {
            return "Study Progress"
        }

        return "\(viewModel.activeSubject) Progress"
    }

    private var progressSectionDescription: String {
        if viewModel.activeSubject.isEmpty {
            return "See what still needs review, what is already learnt, and what is waiting to be saved."
        }

        return "Track saved deck progress for \(viewModel.activeSubject), including reviewed, learnt, and still-learning cards."
    }

    private func refreshProgressSnapshots() {
        progressSnapshots = FlashcardStudyProgressStore.loadAllSnapshots()
    }

    private func progressSnapshot(for flashcardSet: FlashcardSet) -> FlashcardStudyProgressSnapshot {
        let deckID = FlashcardStudyProgressStore.deckID(for: flashcardSet)
        return progressSnapshots[deckID] ?? FlashcardStudyProgressSnapshot.empty(for: flashcardSet)
    }
}

private struct SubjectFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isSelected ? .white : Color(red: 0.11, green: 0.49, blue: 0.95))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isSelected
                    ? Color(red: 0.11, green: 0.49, blue: 0.95)
                    : Color.white
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.blue.opacity(isSelected ? 0 : 0.18), lineWidth: 1.2)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct PendingDraftProgressCard: View {
    let title: String
    let subject: String
    let cardCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.orange.opacity(0.14))
                        .frame(width: 54, height: 54)

                    Image(systemName: "square.and.pencil")
                        .font(.title3)
                        .foregroundColor(Color.orange)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Review, Save, and Study")
                        .font(.headline)
                        .foregroundColor(.black)

                    Text(draftSubtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private var draftSubtitle: String {
        let resolvedTitle = title.isEmpty ? "Untitled Deck" : title
        let subjectPrefix = subject.isEmpty ? "" : "\(subject) • "
        return "\(subjectPrefix)\(resolvedTitle) • \(cardCount) cards still need review before you save"
    }
}

private struct DeckProgressCard: View {
    let flashcardSet: FlashcardSet
    let snapshot: FlashcardStudyProgressSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(flashcardSet.title)
                        .font(.headline)
                        .foregroundColor(.black)

                    Text(deckSubtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                ProgressPill(
                    title: "\(snapshot.reviewedCardCount)/\(snapshot.totalCardCount) reviewed",
                    tint: Color(red: 0.25, green: 0.53, blue: 0.94)
                )

                ProgressPill(
                    title: "\(snapshot.learnedCardCount) learnt",
                    tint: Color(red: 0.45, green: 0.81, blue: 0.49)
                )

                ProgressPill(
                    title: "\(snapshot.stillLearningCardCount) still learning",
                    tint: Color(red: 0.98, green: 0.48, blue: 0.43)
                )
            }

            Text(remainingLine)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var deckSubtitle: String {
        let details = [flashcardSet.subject, flashcardSet.sourceType]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")

        if details.isEmpty {
            return snapshot.hasProgress ? "Latest study progress" : "Ready to study"
        }

        return details
    }

    private var remainingLine: String {
        if snapshot.hasProgress {
            return "\(snapshot.remainingCardCount) cards not reviewed in the latest study round."
        }

        return "No study progress saved yet."
    }
}

private struct ProgressPill: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environment(AppViewModel())
    }
}
