import SwiftUI
import SwiftData

struct StartView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @Query private var allUsers: [User]
    @State private var isAnimating = false
    @State private var didCheckSavedSession = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.43, blue: 0.89),
                    Color(red: 0.13, green: 0.53, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 22) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.95))
                            .frame(width: 220, height: 220)

                        Image("owl_mascot")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 180, height: 180)
                            .clipShape(Circle())
                            .scaleEffect(isAnimating ? 1.08 : 1.0)
                    }
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) {
                            isAnimating = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                isAnimating = false
                            }
                        }
                    }

                    VStack(spacing: 10) {
                        Text("SmartDeck")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("Study smarter, not harder.")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.94))

                        Text("Turn notes into flashcards, find nearby libraries, and build a daily study habit.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.88))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 34)
                    }
                }

                Spacer()

                VStack(spacing: 16) {
                    NavigationLink(value: NavTarget.signup) {
                        Text("Create Account")
                            .font(.headline)
                            .foregroundColor(Color(red: 0.11, green: 0.49, blue: 0.95))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(AppTheme.surface)
                            .clipShape(Capsule())
                    }

                    NavigationLink(value: NavTarget.login) {
                        Text("I Already Have an Account")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                            )
                    }

                    Text("Double-tap the owl for a little good luck.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.78))
                        .padding(.top, 4)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 46)
            }
        }
        .onAppear {
            attemptSessionRestore()
        }
        .onChange(of: allUsers.count) { _, _ in
            attemptSessionRestore()
        }
    }

    private func attemptSessionRestore() {
        guard !didCheckSavedSession else { return }

        guard let destination = viewModel.restorePersistedSession(modelContext: modelContext) else {
            return
        }

        didCheckSavedSession = true

        DispatchQueue.main.async {
            viewModel.navPath = NavigationPath()
            viewModel.navPath.append(destination)
        }
    }
}

#Preview {
    NavigationStack {
        StartView()
    }
}
