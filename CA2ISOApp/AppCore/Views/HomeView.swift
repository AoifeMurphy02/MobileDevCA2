//
//  Home.swift
//  CA2ISOApp
//
//  Created by Aoife on 24/03/2026.
//

import Foundation
import SwiftUI

struct HomeView: View {
    @Environment(AppViewModel.self) private var viewModel
        
    
    // Colors for the subject cards
    let cardColors: [Color] = [.orange, .red, .purple, .pink, .green, .blue]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. HEADER (Profile, Welcome, Streak)
            HStack {
                Circle()
                    .fill(.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay(Image(systemName: "person.fill").foregroundColor(.white))
                
                Text("Welcome Back!")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                
                Spacer()
                
                HStack(spacing: 5) {
                    Text("🔥 \(viewModel.streakCount)")
                    Image(systemName: "heart")
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            .padding(.top, 20)

            // 2. SUBJECTS SECTION
            Text("Subjects")
                .font(.headline)
                .foregroundColor(.blue)
                .padding(.horizontal)
                .padding(.top, 30)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    // Loop through subjects added from SubjectPickerView
                    ForEach(Array(viewModel.chosenSubjects.enumerated()), id: \.offset) { index, subject in
                        SubjectCard(
                            title: subject,
                            color: cardColors[index % cardColors.count]
                        )
                    }
                    
                    // Fallback if list is empty
                    if viewModel.chosenSubjects.isEmpty {
                        Text("No subjects added yet.")
                            .foregroundColor(.gray)
                            .padding()
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)
            }

            
            

            Spacer()

            
        }
        .navigationBarBackButtonHidden(true)
    }
}


struct SubjectCard: View {
    var title: String
    var color: Color
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            Spacer()
            Image(systemName: "brain.head.profile") // Placeholder for your icons
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding()
        .frame(width: 160, height: 120)
        .background(color)
        .cornerRadius(20)
    }
}





#Preview {
    HomeView()
        .environment(AppViewModel())
}
