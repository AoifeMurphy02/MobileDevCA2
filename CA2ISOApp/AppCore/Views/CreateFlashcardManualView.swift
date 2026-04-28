//
//  CreateFlashcardManualView.swift
//  CA2ISOApp
//
//  Created by Aoife on 14/04/2026.
//

import Foundation
import SwiftUI

struct CreateFlashcardManualView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    
    // 1. Interaction State
    @State private var selectedSubject = ""
    @State private var topic = ""
    @State private var flashcardTitle = ""
    @State private var question = ""
    @State private var answer = ""
    @State private var errorMessage = ""
    @State private var showErrorAlert = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                // HEADER (Matches your prototype)
                HStack(spacing: 15) {
                    Circle()
                        .fill(.gray.opacity(0.3))
                        .frame(width: 50, height: 50)
                        .overlay(Image(systemName: "person.fill").foregroundColor(.white))
                    
                    Text("Create Flashcards")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.11, green: 0.49, blue: 0.95))
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 20)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                       
                        Group {
                            ManualInputField(label: "Subject", text: $selectedSubject, isPicker: true, subjects: viewModel.subjectOptions)
                            ManualInputField(label: "Topic", text: $topic)
                            ManualInputField(label: "Deck Title", text: $flashcardTitle)
                        }

                        Text("Create your first card here, then continue to the deck editor to add, remove, or reorder the rest.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        // Question and Answer
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Term / Question").fontWeight(.bold)
                            TextEditorView(text: $question)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Answer").fontWeight(.bold)
                            TextEditorView(text: $answer)
                        }

                    
                        HStack {
                            Spacer()
                            Button(action: {
                                saveManualFlashcard()
                            }) {
                                Text("Continue to Deck Builder")
                                    .fontWeight(.bold)
                                    .foregroundColor(Color.blue)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 60)
                                    .background(
                                        Capsule().stroke(Color.blue.opacity(0.5), lineWidth: 1.5)
                                    )
                            }
                            Spacer()
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 100) // Extra space for Nav Bar
                    }
                    .padding(25)
                }
            }
            
            CustomNavBar(selectedTab: 1)
        }
        .navigationBarBackButtonHidden(true)
        .enableSwipeBack()
        .onAppear {
            if selectedSubject.isEmpty {
                selectedSubject = viewModel.defaultSubjectForCreation
            }
        }
        .alert("Could not save flashcard", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func saveManualFlashcard() {
        let resolvedSubject = selectedSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = flashcardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !resolvedQuestion.isEmpty, !resolvedAnswer.isEmpty else {
            errorMessage = "Please add both a question and an answer before building the deck."
            showErrorAlert = true
            return
        }

        let deckDraft = FlashcardDeckDraft(
            title: resolvedTitle.isEmpty ? "Manual Flashcards" : resolvedTitle,
            sourceType: "Manual Entry",
            subject: resolvedSubject,
            topic: resolvedTopic,
            rawText: "\(resolvedQuestion)\n\(resolvedAnswer)",
            cards: [
                FlashcardDraft(
                    question: resolvedQuestion,
                    answer: resolvedAnswer,
                    style: resolvedQuestion.lowercased().hasPrefix("what is") ? .definition : .summary
                )
            ]
        )

        viewModel.loadFlashcardDraft(deckDraft)
        //dismiss()

        DispatchQueue.main.async {
            viewModel.navPath.append(NavTarget.flashcardReview)
        }
    }
}


struct ManualInputField: View {
    let label: String
    @Binding var text: String
    var isPicker: Bool = false
    var subjects: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).fontWeight(.bold)
            
            if isPicker {
                Picker(label, selection: $text) {
                    Text("Select Subject").tag("")
                    ForEach(subjects, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(.black)
            } else {
                TextField("", text: $text)
            }
            
            Divider().background(Color.blue.opacity(0.5))
        }
    }
}

struct TextEditorView: View {
    @Binding var text: String
    var body: some View {
        TextEditor(text: $text)
            .frame(height: 120)
            .padding(10)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1.5)
            )
    }
}

#Preview {
    let model = AppViewModel()
    model.chosenSubjects = ["English", "Maths"]
    return CreateFlashcardManualView().environment(model)
}
