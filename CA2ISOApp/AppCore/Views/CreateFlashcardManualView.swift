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
    
    // Interaction State
    @State private var selectedSubject = ""
    @State private var topic = ""
    @State private var flashcardTitle = ""
    @State private var question = ""
    @State private var answer = ""
    @State private var errorMessage = ""
    @State private var showErrorAlert = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Background color matching the review view
            Color(red: 0.98, green: 0.99, blue: 1.0).ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 0) {
                // HEADER
                HStack(spacing: 15) {
                    Circle()
                        .fill(.gray.opacity(0.3))
                        .frame(width: 45, height: 45)
                        .overlay(Image(systemName: "person.fill").foregroundColor(.white))
                    
                    Text("Create Flashcards")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.11, green: 0.49, blue: 0.95))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 15)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        
                        manualModeSummary
                        
                       
                        deckDetailsSection
                        
                        
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Initial Card")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Term / Question").font(.subheadline.weight(.semibold))
                                ManualEditorTextBox(text: $question, placeholder: "e.g. What is Photosynthesis?", minHeight: 100)
                            }
                            
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Answer").font(.subheadline.weight(.semibold))
                                ManualEditorTextBox(text: $answer, placeholder: "e.g. The process by which plants make food.", minHeight: 120)
                            }
                        }
                        .padding(18)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: .black.opacity(0.04), radius: 12, y: 6)
                        
                        
                        Button(action: saveManualFlashcard) {
                            Text("Continue to Deck Builder")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color(red: 0.11, green: 0.49, blue: 0.95))
                                .clipShape(Capsule())
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 120) // Space for Nav Bar
                    }
                    .padding(20)
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
    
    
    private var manualModeSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create your card deck manually. You can add more cards, reorder them, or use AI tools to expand your deck.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 10) {
                ManualStatPill(title: "Manual Entry", tint: .green)
                ManualStatPill(title: "Draft Mode", tint: .orange)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 6)
    }
    
    private var deckDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Deck Details")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Subject").font(.subheadline.weight(.semibold))
                // Reuse your existing subject picker or style a textfield
                TextField("e.g. Biology", text: $selectedSubject)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                if !viewModel.subjectOptions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.subjectOptions, id: \.self) { subject in
                                Button { selectedSubject = subject } label: {
                                    Text(subject)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(selectedSubject == subject ? .white : .blue)
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(selectedSubject == subject ? Color.blue : Color.blue.opacity(0.05))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Topic").font(.subheadline.weight(.semibold))
                TextField("e.g. Chapter 4", text: $topic)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Deck Title").font(.subheadline.weight(.semibold))
                TextField("e.g. Midterm Prep", text: $flashcardTitle)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 6)
    }

    private func saveManualFlashcard() {
        let resolvedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !resolvedQuestion.isEmpty, !resolvedAnswer.isEmpty else {
            errorMessage = "Please add both a question and an answer."
            showErrorAlert = true
            return
        }
        
        let newManualCard = FlashcardDraft(
            question: resolvedQuestion,
            answer: resolvedAnswer,
            style: resolvedQuestion.lowercased().hasPrefix("what is") ? .definition : .summary
        )
        
        let deckDraft = FlashcardDeckDraft(
            title: flashcardTitle.isEmpty ? "Manual Deck" : flashcardTitle,
            sourceType: "Manual Entry",
            subject: selectedSubject,
            topic: topic,
            rawText: "Manual Input",
            cards: [newManualCard]
        )
        
        viewModel.loadFlashcardDraft(deckDraft)
        
        DispatchQueue.main.async {
            viewModel.navPath.append(NavTarget.flashcardReview)
        }
    }
}


struct ManualEditorTextBox: View {
    @Binding var text: String
    var placeholder: String
    let minHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(.gray.opacity(0.5))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
            }
            
            TextEditor(text: $text)
                .frame(minHeight: minHeight)
                .padding(10)
                .scrollContentBackground(.hidden) // Makes background color work
                .background(Color(red: 0.98, green: 0.99, blue: 1.0))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.16), lineWidth: 1.2)
                )
        }
    }
}

struct ManualStatPill: View {
    let title: String
    let tint: Color
    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}
