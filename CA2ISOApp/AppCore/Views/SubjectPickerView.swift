//
//  SubjectPickerView.swift
//  CA2ISOApp
//
//  Created by Aoife on 27/03/2026.
//

import Foundation
import SwiftUI
import SwiftData

struct SubjectPickerView: View {
    // State to track multiple selections
    @Environment(AppViewModel.self) private var viewModel
        
    @State private var selectedSubjects: Set<String> = []
   
    
    @State private var navigateToHome = false
    @Environment(\.modelContext) private var modelContext
    @Query var allUsers: [User]

    
    @State private var subjects = [
        "English", "French", "German", "Spanish", "Mathematics",
        "Physics", "Biology", "Chemistry", "Computer Science",
        "Geography", "History", "Music", "Art"
    ]
    
    @State private var newSubjectName: String = ""


    var body: some View {
        ZStack {
            // Background Blue
            Color(red: 0.11, green: 0.49, blue: 0.95).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Blue Area (Status bar space)
                Spacer().frame(height: 60)
                
                // White Card
                VStack(spacing: 0) {
                    Text("Pick Your Subjects")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.11, green: 0.49, blue: 0.95))
                        .padding(.top, 40)
                        .padding(.bottom, 20)
                    
            
                        HStack(spacing: 15) {
                                            TextField("Type new subject...", text: $newSubjectName)
                                                .padding()
                                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
                                                .textInputAutocapitalization(.words) // Automatically capitals first letter
                                            
                                            Button(action: addNewSubject) {
                                                Image(systemName: "plus.circle.fill")
                                                    .font(.system(size: 40))
                                                    .foregroundColor(newSubjectName.isEmpty ? .gray : .blue)
                                                
                                                
                                            }
                                            .disabled(newSubjectName.isEmpty) // Disable button if empty
                                        }
                                        .padding(.horizontal, 30)
                                        .padding(.top, 20)
                                        .padding(.bottom, 10)
                                        
                    
                    ScrollView {
                        VStack(spacing: 15) {
                            ForEach(subjects, id: \.self) { subject in
                                SubjectRow(
                                    title: subject,
                                    isSelected: selectedSubjects.contains(subject)
                                )
                                .onTapGesture {
                                    // Toggle selection logic
                                    if selectedSubjects.contains(subject) {
                                        selectedSubjects.remove(subject)
                                    } else {
                                        selectedSubjects.insert(subject)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 30)
                    }
                    
                    // Sticky Bottom Button Area
                
                    VStack {
                        Button(action: {
                           
                            viewModel.chosenSubjects = Array(selectedSubjects)
                            viewModel.persistSubjectsToDatabase(modelContext: modelContext, users: allUsers)
                            
                            navigateToHome = true
                        }) {
                            Text(selectedSubjects.isEmpty ? "Select Subjects" : "Add Subjects")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(selectedSubjects.isEmpty ? Color.gray : Color(red: 0.11, green: 0.49, blue: 0.95))
                                .clipShape(Capsule())
                        }
                        .disabled(selectedSubjects.isEmpty)
                        .padding(.horizontal, 40)
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                    }
                    .background(Color.white)
                }
                
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40))
            }
            .ignoresSafeArea(edges: .bottom)
        }.navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            
            // Load existing subjects when the screen opens
            .onAppear {
                // We take the subjects already in the ViewModel
                // and put them into the local 'selectedSubjects' Set
                for subject in viewModel.chosenSubjects {
                    selectedSubjects.insert(subject)
                }
            }
            
            .navigationDestination(isPresented: $navigateToHome) {
                HomeView()
            }
        
       
    }

func addNewSubject() {
       let trimmedName = newSubjectName.trimmingCharacters(in: .whitespaces)
       
       // Validation: Don't add if empty or if it already exists
       if !trimmedName.isEmpty && !subjects.contains(trimmedName) {
           withAnimation(.spring()) {
               subjects.insert(trimmedName, at: 0) // Adds to the top of the list
               selectedSubjects.insert(trimmedName) // Automatically select it
               newSubjectName = "" // Clear the text field
           }
       }
   }
}

struct SubjectRow: View {
    var title: String
    var isSelected: Bool
    
    var body: some View {
        HStack {
            Text(title)
                .fontWeight(.medium)
            
            Spacer()
            
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 15).fill(Color.gray.opacity(0.1)))
        
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
        // Animation makes the border fade in smoothly
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}


#Preview {
    NavigationStack {
        SubjectPickerView()
            .environment(AppViewModel())
    }
}
