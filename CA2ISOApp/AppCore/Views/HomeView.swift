import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    
    @Query var allUsers: [User]
    @Query(sort: \FlashcardSet.createdAt, order: .reverse) private var flashcardSets: [FlashcardSet]
    
    @State private var showProfileSheet = false
    @State private var dashboardFlashcardSets: [FlashcardSet] = []
    @State private var progressSnapshots: [String: FlashcardStudyProgressSnapshot] = [:]

    // Logic to filter the deck library based on the selected study space
    private var visibleSets: [FlashcardSet] {
        FlashcardSetVisibility.visibleSets(
            dashboardSets,
            currentUserEmail: viewModel.activeSessionEmailForUI,
            totalUserCount: allUsers.count,
            activeStudyArea: viewModel.activestudyArea
        )
    }

    private var dashboardSets: [FlashcardSet] {
        dashboardFlashcardSets.isEmpty ? flashcardSets : dashboardFlashcardSets
    }

    var body: some View {
        // We do NOT use @Bindable here. We connect the sheet manually.
        // This is the ONLY way to bypass the 'Binding<Area>' error
        // without renaming everything in your app.
        let showSheet = Binding(
            get: { viewModel.showCreateSheet },
            set: { viewModel.showCreateSheet = $0 }
        )
        
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    headerCard
                    studyAreaSection
                    
                    // Display decks first as requested
                    librarySection
                    
                    // Display detailed progress tracking
                    progressSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 100)
            }

            // Centralized Navigation Bar
            CustomNavBar(selectedTab: 0)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .disableSwipeBack()
        .sheet(isPresented: showSheet) {
            CreateResourceView().presentationDetents([.medium])
        }
        .sheet(isPresented: $showProfileSheet) {
            ProfileSheetView(
                email: viewModel.activeSessionEmailForUI ?? "",
                streakCount: viewModel.streakCount,
                studyAreaCount: viewModel.studyAreaOptions.count,
                logoutAction: {
                    showProfileSheet = false
                    viewModel.logout()
                }
            )
            .presentationDetents([.medium])
        }
        .onAppear {
            viewModel.syncCurrentUserState(modelContext: modelContext)
            refreshDashboardDecks()
            refreshProgressSnapshots()
            StudyNotificationManager.requestAuthorizationIfNeeded()
            StudyNotificationManager.refreshDailyStudyReminder()
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active {
                viewModel.syncCurrentUserState(modelContext: modelContext)
                refreshDashboardDecks()
                refreshProgressSnapshots()
            }
        }
        .onChange(of: flashcardSets.count) { _, _ in
            refreshDashboardDecks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .flashcardStudyProgressDidChange)) { _ in
            refreshProgressSnapshots()
        }
    }
    
    // MARK: - Subviews

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
                    Button {
                        showProfileSheet = true
                    } label: {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }

                    Label("\(viewModel.streakCount) day streak", systemImage: "flame.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)

                    Text("\(visibleSets.count) decks saved")
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
                colors: [Color(red: 0.11, green: 0.49, blue: 0.95), Color(red: 0.25, green: 0.53, blue: 0.94)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }

    private var studyAreaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Study Spaces").font(.headline)
                Spacer()
                Button {
                    viewModel.navPath.append(NavTarget.studyAreaPicker)
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3").font(.subheadline.weight(.semibold))
                }
            }

            if viewModel.studyAreaOptions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No spaces yet").font(.headline)
                    Text("Pick Areas to organize your decks.").font(.subheadline).foregroundColor(.secondary)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading).background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        studyAreaFilterChip(title: "All", isSelected: viewModel.activestudyArea.isEmpty) {
                            viewModel.selectstudyArea("")
                        }

                        ForEach(viewModel.studyAreaOptions, id: \.self) { name in
                            studyAreaFilterChip(title: name, isSelected: viewModel.activestudyArea == name) {
                                viewModel.selectstudyArea(name)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.activestudyArea.isEmpty ? "Recent Decks" : "\(viewModel.activestudyArea) Decks")
                .font(.headline)

            if visibleSets.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No decks yet").font(.headline)
                    Text("Start creating flashcards to build your library.").font(.subheadline).foregroundColor(.secondary)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading).background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                ForEach(visibleSets.prefix(8)) { set in
                    NavigationLink(value: NavTarget.flashcardSetDetail(set)) {
                        FlashcardSetCard(flashcardSet: set)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progress").font(.headline)

            if shouldShowDraftProgressCard {
                PendingDraftProgressCard(
                    title: viewModel.flashcardDraftTitle,
                    studyArea: viewModel.flashcardDraftstudyArea,
                    cardCount: viewModel.flashcardDraftCards.count
                ) {
                    viewModel.navPath.append(NavTarget.flashcardReview)
                }
            }

            if !visibleSets.isEmpty {
                ForEach(visibleSets.prefix(6)) { set in
                    NavigationLink {
                        FlashcardSetDetailView(flashcardSet: set, shouldResumeProgress: true)
                    } label: {
                        DeckProgressCard(flashcardSet: set, snapshot: progressSnapshot(for: set))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Logic Helpers
    
    private var homeTitle: String {
        if let email = viewModel.activeSessionEmailForUI { return email.components(separatedBy: "@").first ?? email }
        return "Study Hub"
    }

    private var headerDescription: String {
        viewModel.activestudyArea.isEmpty ? "View your learning stats and jump back into recent decks." : "Focusing on \(viewModel.activestudyArea)."
    }

    private var shouldShowDraftProgressCard: Bool {
        guard viewModel.hasFlashcardDraft else { return false }

        return viewModel.activestudyArea.isEmpty ||
            viewModel.flashcardDraftstudyArea.isEmpty ||
            viewModel.flashcardDraftstudyArea == viewModel.activestudyArea
    }

    private func progressSnapshot(for set: FlashcardSet) -> FlashcardStudyProgressSnapshot {
        let deckID = FlashcardStudyProgressStore.deckID(for: set)
        return progressSnapshots[deckID] ?? FlashcardStudyProgressStore.snapshot(for: set)
    }

    private func refreshDashboardDecks() {
        var descriptor = FetchDescriptor<FlashcardSet>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 80
        dashboardFlashcardSets = (try? modelContext.fetch(descriptor)) ?? flashcardSets
        print("DEBUG: Home fetched \(dashboardFlashcardSets.count) saved decks from SwiftData.")
    }

    private func refreshProgressSnapshots() {
        progressSnapshots = FlashcardStudyProgressStore.loadAllSnapshots()
    }
}

private struct ProfileSheetView: View {
    let email: String
    let streakCount: Int
    let studyAreaCount: Int
    let logoutAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Profile")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.primary)

            VStack(alignment: .leading, spacing: 12) {
                ProfileInfoRow(title: "Signed in as", value: email.isEmpty ? "Unknown account" : email)
                ProfileInfoRow(title: "Study spaces", value: "\(studyAreaCount)")
                ProfileInfoRow(title: "Current streak", value: "\(streakCount) days")
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Button(role: .destructive, action: logoutAction) {
                Text("Log Out")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.red)
                    .clipShape(Capsule())
            }

            Spacer()
        }
        .padding(24)
    }
}

private struct ProfileInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            Text(value)
                .font(.headline)
                .foregroundColor(AppTheme.text)
        }
    }
}


private struct studyAreaFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isSelected ? .white : AppTheme.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isSelected
                    ? AppTheme.primary
                    : AppTheme.surface
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
    let studyArea: String
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
                        .foregroundColor(AppTheme.text)

                    Text(draftSubtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private var draftSubtitle: String {
        
        let resolvedTitle = title.isEmpty ? "Untitled Deck" : title
        let studyAreaPrefix = studyArea.isEmpty ? "" : "\(studyArea) • "
        return "\(studyAreaPrefix)\(resolvedTitle) • \(cardCount) cards still need review before you save"
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
                        .foregroundColor(AppTheme.text)

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
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var deckSubtitle: String {
       // let details = [flashcardSet.studyArea, flashcardSet.sourceType]
        let details = [flashcardSet.studyArea, flashcardSet.sourceType]
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
