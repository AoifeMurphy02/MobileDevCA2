import Foundation
import SwiftData
import SwiftUI

struct studyAreaPickerView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext

    @State private var selectedstudyAreas: Set<String> = []
    @State private var studyAreas = [
        "English", "French", "German", "Spanish", "Mathematics",
        "Physics", "Biology", "Chemistry", "Computer Science",
        "Geography", "History", "Business", "Music", "Art"
    ]
    @State private var newstudyAreaName = ""

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
                        Text("Choose Your studyAreas")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 0.11, green: 0.49, blue: 0.95))

                        Text("studyAreas act like study spaces. They organize your decks, power AI suggestions, and make the home screen easier to understand.")
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
                        Text("Add a custom studyArea")
                            .font(.headline)
                            .padding(.horizontal, 26)

                        HStack(spacing: 12) {
                            TextField("Type a studyArea name", text: $newstudyAreaName)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.gray.opacity(0.08))
                                )
                                .textInputAutocapitalization(.words)

                            Button(action: addNewstudyArea) {
                                Image(systemName: "plus")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(width: 48, height: 48)
                                    .background(
                                        Circle()
                                            .fill(newstudyAreaName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                                    )
                            }
                            .disabled(newstudyAreaName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.horizontal, 26)
                    }

                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(studyAreas, id: \.self) { studyArea in
                                studyAreaSelectionChip(
                                    title: studyArea,
                                    isSelected: selectedstudyAreas.contains(studyArea)
                                )
                                .onTapGesture {
                                    togglestudyArea(studyArea)
                                }
                            }
                        }
                        .padding(.horizontal, 26)
                        .padding(.top, 22)
                        .padding(.bottom, 24)
                    }

                    VStack(spacing: 14) {
                        Button(action: savestudyAreasAndContinue) {
                            Text(selectedstudyAreas.isEmpty ? "Choose at Least One studyArea" : continueButtonTitle)
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(selectedstudyAreas.isEmpty ? Color.gray : Color(red: 0.11, green: 0.49, blue: 0.95))
                                .clipShape(Capsule())
                        }
                        .disabled(selectedstudyAreas.isEmpty)

                        if !viewModel.studyAreaOptions.isEmpty {
                            Button("Keep Existing studyAreas") {
                                viewModel.goHome()
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
        .disableSwipeBack()
        .onAppear {
            syncSelectedstudyAreas()
        }
    }

    private var continueButtonTitle: String {
        viewModel.studyAreaOptions.isEmpty ? "Continue to Home" : "Save studyAreas"
    }

    private func syncSelectedstudyAreas() {
        for studyArea in viewModel.studyAreaOptions {
            if !studyAreas.contains(studyArea) {
                studyAreas.insert(studyArea, at: 0)
            }
            selectedstudyAreas.insert(studyArea)
        }
    }

    private func togglestudyArea(_ studyArea: String) {
        if selectedstudyAreas.contains(studyArea) {
            selectedstudyAreas.remove(studyArea)
        } else {
            selectedstudyAreas.insert(studyArea)
        }
    }

    private func addNewstudyArea() {
        let trimmedName = newstudyAreaName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, !studyAreas.contains(trimmedName) else { return }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            studyAreas.insert(trimmedName, at: 0)
            selectedstudyAreas.insert(trimmedName)
            newstudyAreaName = ""
        }
    }

    private func savestudyAreasAndContinue() {
        let orderedSelection = studyAreas.filter { selectedstudyAreas.contains($0) }

        viewModel.applyChosenstudyAreas(orderedSelection)
        if let firststudyArea = orderedSelection.first {
            viewModel.selectstudyArea(firststudyArea)
        }
        viewModel.persiststudyAreasToDatabase(modelContext: modelContext)
        viewModel.goHome()
    }
}

private struct studyAreaSelectionChip: View {
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
        studyAreaPickerView()
            .environment(AppViewModel())
    }
}
