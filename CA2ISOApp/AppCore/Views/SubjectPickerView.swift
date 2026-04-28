import Foundation
import SwiftData
import SwiftUI

struct SubjectPickerView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @Query var allUsers: [User]

    @State private var selectedSubjects: Set<String> = []
    @State private var navigateToHome = false
    @State private var subjects = [
        "English", "French", "German", "Spanish", "Mathematics",
        "Physics", "Biology", "Chemistry", "Computer Science",
        "Geography", "History", "Business", "Music", "Art"
    ]
    @State private var newSubjectName = ""

    private let columns = [
        GridItem(.adaptive(minimum: 140), spacing: 12)
    ]

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
                    .frame(height: 54)

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choose Your Subjects")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 0.11, green: 0.49, blue: 0.95))

                        Text("Subjects act like study spaces. They organize your decks, power AI suggestions, and make the home screen easier to understand.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("You can always edit these later.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 34)
                    .padding(.bottom, 24)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Add a custom subject")
                            .font(.headline)
                            .padding(.horizontal, 26)

                        HStack(spacing: 12) {
                            TextField("Type a subject name", text: $newSubjectName)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.gray.opacity(0.08))
                                )
                                .textInputAutocapitalization(.words)

                            Button(action: addNewSubject) {
                                Image(systemName: "plus")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(width: 48, height: 48)
                                    .background(
                                        Circle()
                                            .fill(newSubjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                                    )
                            }
                            .disabled(newSubjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.horizontal, 26)
                    }

                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(subjects, id: \.self) { subject in
                                SubjectSelectionChip(
                                    title: subject,
                                    isSelected: selectedSubjects.contains(subject)
                                )
                                .onTapGesture {
                                    toggleSubject(subject)
                                }
                            }
                        }
                        .padding(.horizontal, 26)
                        .padding(.top, 22)
                        .padding(.bottom, 24)
                    }

                    VStack(spacing: 14) {
                        Button(action: saveSubjectsAndContinue) {
                            Text(selectedSubjects.isEmpty ? "Choose at Least One Subject" : continueButtonTitle)
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(selectedSubjects.isEmpty ? Color.gray : Color(red: 0.11, green: 0.49, blue: 0.95))
                                .clipShape(Capsule())
                        }
                        .disabled(selectedSubjects.isEmpty)

                        if !viewModel.subjectOptions.isEmpty {
                            Button("Keep Existing Subjects") {
                                navigateToHome = true
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Color(red: 0.11, green: 0.49, blue: 0.95))
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 10)
                    .padding(.bottom, 34)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40))
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .enableSwipeBack()
        .onAppear {
            syncSelectedSubjects()
        }
        .navigationDestination(isPresented: $navigateToHome) {
            HomeView()
        }
    }

    private var continueButtonTitle: String {
        viewModel.subjectOptions.isEmpty ? "Continue to Home" : "Save Subjects"
    }

    private func syncSelectedSubjects() {
        for subject in viewModel.subjectOptions {
            if !subjects.contains(subject) {
                subjects.insert(subject, at: 0)
            }
            selectedSubjects.insert(subject)
        }
    }

    private func toggleSubject(_ subject: String) {
        if selectedSubjects.contains(subject) {
            selectedSubjects.remove(subject)
        } else {
            selectedSubjects.insert(subject)
        }
    }

    private func addNewSubject() {
        let trimmedName = newSubjectName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, !subjects.contains(trimmedName) else { return }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            subjects.insert(trimmedName, at: 0)
            selectedSubjects.insert(trimmedName)
            newSubjectName = ""
        }
    }

    private func saveSubjectsAndContinue() {
        let orderedSelection = subjects.filter { selectedSubjects.contains($0) }

        viewModel.applyChosenSubjects(orderedSelection)
        if let firstSubject = orderedSelection.first {
            viewModel.selectSubject(firstSubject)
        }
        viewModel.persistSubjectsToDatabase(modelContext: modelContext, users: allUsers)

        navigateToHome = true
    }
}

private struct SubjectSelectionChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .white : Color(red: 0.11, green: 0.49, blue: 0.95))

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isSelected ? .white : .black)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? Color(red: 0.11, green: 0.49, blue: 0.95) : Color.gray.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.clear : Color.blue.opacity(0.14), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        SubjectPickerView()
            .environment(AppViewModel())
    }
}
