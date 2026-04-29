import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Query(sort: \FlashcardSet.createdAt, order: .reverse) private var flashcardSets: [FlashcardSet]

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

                        // If draft exists, it sits  near the cards
                        if viewModel.hasFlashcardDraft {
                            FlashcardResumeDraftCard(
                                title: viewModel.flashcardDraftTitle,
                                cardCount: viewModel.flashcardDraftCards.count
                            ) {
                                viewModel.navPath.append(NavTarget.flashcardReview)
                            }
                        }

                        // quick actions
                        quickActionsSection
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

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            VStack(spacing: 12) {
                HomeActionCard(
                    title: "Create AI Flashcards",
                    subtitle: "Import notes, files, or images and turn them into ranked study cards.",
                    icon: "sparkles.rectangle.stack",
                    tint: Color(red: 0.25, green: 0.53, blue: 0.94)
                ) {
                    viewModel.navPath.append(NavTarget.flashcards)
                }

                HomeActionCard(
                    title: "Manual Deck Builder",
                    subtitle: "Start with one card and edit the rest in the deck review flow.",
                    icon: "square.and.pencil",
                    tint: Color(red: 0.0, green: 0.63, blue: 0.55)
                ) {
                    viewModel.navPath.append(NavTarget.createFlashcardsManually)
                }

                HomeActionCard(
                    title: "Open Study Timer",
                    subtitle: "Use focused study sessions and keep your routine consistent.",
                    icon: "timer",
                    tint: Color(red: 0.95, green: 0.57, blue: 0.18)
                ) {
                    viewModel.navPath.append(NavTarget.timer)
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

private struct HomeActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(tint.opacity(0.14))
                        .frame(width: 54, height: 54)

                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(tint)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.black)

                    Text(subtitle)
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
}

#Preview {
    NavigationStack {
        HomeView()
            .environment(AppViewModel())
    }
}
