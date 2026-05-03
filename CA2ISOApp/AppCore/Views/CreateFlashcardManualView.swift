//
//  CreateFlashcardManualView.swift
//  CA2ISOApp
//
//  Created by Aoife on 14/04/2026.
//

import Foundation
import SwiftUI
import SwiftData

struct CreateFlashcardManualView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    
    // 1. Array of cards for multi-card creation
    @State private var cards: [FlashcardDraft] = [FlashcardDraft(question: "", answer: "")]
    
    // Interaction State
    @State private var selectedstudySubject = ""
    @State private var topic = ""
    @State private var flashcardTitle = ""
    @State private var errorMessage = ""
    @State private var showErrorAlert = false
    
    var body: some View {
        @Bindable var viewModel = viewModel
        
        ZStack(alignment: .bottom) {
            Color(red: 0.98, green: 0.99, blue: 1.0).ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        manualModeSummary
                        deckDetailsSection
                        
                        // 2. DYNAMIC CARD LIST
                        Text("Cards (\(cards.count))")
                            .font(.headline)
                            .padding(.horizontal, 5)
                        
                        ForEach($cards) { $card in
                            ManualCardEditor(
                                card: $card,
                                index: cards.firstIndex(where: { $0.id == card.id }) ?? 0
                            ) {
                                // Delete logic
                                if cards.count > 1 {
                                    withAnimation {
                                        cards.removeAll(where: { $0.id == card.id })
                                    }
                                }
                            }
                        }
                        
                        // 3. ADD CARD BUTTON (+)
                        Button(action: {
                            withAnimation(.spring()) {
                                cards.append(FlashcardDraft(question: "", answer: ""))
                            }
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Another Card")
                            }
                            .font(.headline)
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 15).stroke(Color.blue.opacity(0.3), lineWidth: 1.5))
                        }
                        .padding(.bottom, 150) // Space for sticky save button and Nav Bar
                    }
                    .padding(20)
                }
            }
            
            // 4. STICKY SAVE BUTTON AREA
            VStack(spacing: 0) {
                Button(action: saveEntireDeck) {
                    Text("Save Full Deck")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canSave ? Color(red: 0.11, green: 0.49, blue: 0.95) : Color.gray)
                        .clipShape(Capsule())
                }
                .disabled(!canSave)
                .padding(.horizontal, 25)
                .padding(.top, 15)
                .padding(.bottom, 10)
                .background(Color.white.shadow(color: .black.opacity(0.05), radius: 5, y: -5))
                
                CustomNavBar(selectedTab: 1)
            }
        }
        .navigationBarBackButtonHidden(true)
        .enableSwipeBack()
        .onAppear {
            if selectedstudySubject.isEmpty {
                selectedstudySubject = viewModel.defaultstudySubjectForCreation
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    
    var canSave: Bool {
        // Form is valid if Title is set and at least one card has both Q and A
        !flashcardTitle.isEmpty && !cards.filter({ $0.question.isEmpty || $0.answer.isEmpty }).isEmpty == false
    }
    
    private var headerSection: some View {
        HStack(spacing: 15) {
            Circle().fill(.gray.opacity(0.3)).frame(width: 45, height: 45)
                .overlay(Image(systemName: "person.fill").foregroundColor(.white))
            Text("Deck Builder").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundColor(.blue)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 15)
    }
    
    private var manualModeSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create your card deck manually. You can add more cards, reorder them, or use AI tools to expand your deck.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 10) {
                ManualStatPill(title: "Manual Entry", tint: .green)
                ManualStatPill(title: "Persistent Mode", tint: .blue)
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
            Text("Deck Details").font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("studySubject").font(.subheadline.weight(.semibold))
                TextField("e.g. Biology", text: $selectedstudySubject)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                if !viewModel.studySubjectOptions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.studySubjectOptions, id: \.self) { studySubject in
                                Button { selectedstudySubject = studySubject } label: {
                                    Text(studySubject)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(selectedstudySubject == studySubject ? .white : .blue)
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(selectedstudySubject == studySubject ? Color.blue : Color.blue.opacity(0.05))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
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

    private func saveEntireDeck() {
        // Create the persistent FlashcardSet (The Model)
        let newSet = FlashcardSet(
            title: flashcardTitle,
            sourceType: "Manual Entry",
            studySubject: selectedstudySubject,
            topic: topic,
            rawText: "Manual Input"
        )
        
        // Add all cards to the set
        for (cardIndex, draft) in cards.enumerated() {
                if !draft.question.isEmpty && !draft.answer.isEmpty {
                    let realCard = Flashcard(
                        question: draft.question,
                        answer: draft.answer,
                        orderIndex: cardIndex,
                        parentSet: newSet
                    )
                    newSet.cards.append(realCard)
                }
            }
        
        // Save to SwiftData
        modelContext.insert(newSet)
        
        do {
            try modelContext.save()
            print("SUCCESS: Full manual deck saved.")
            // Return to Home
            viewModel.navPath = NavigationPath()
            viewModel.navPath.append(NavTarget.home)
        } catch {
            errorMessage = "Could not save to database: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
}

struct ManualCardEditor: View {
    @Binding var card: FlashcardDraft
    let index: Int
    var deleteAction: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Card \(index + 1)").font(.subheadline.bold()).foregroundColor(.gray)
                Spacer()
                Button(action: deleteAction) {
                    Image(systemName: "trash").foregroundColor(.red.opacity(0.7))
                }
            }
            
            ManualEditorTextBox(text: $card.question, placeholder: "Question...", minHeight: 80)
            ManualEditorTextBox(text: $card.answer, placeholder: "Answer...", minHeight: 100)
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 10, y: 5)
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
                .scrollContentBackground(.hidden)
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

#Preview {
    let model = AppViewModel()
    model.chosenstudySubjects = ["English", "Maths"]
    return CreateFlashcardManualView().environment(model)
}
