//
//  Home.swift
//  CA2ISOApp
//
//  Created by Aoife on 24/03/2026.
//

import Foundation
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
    let cardColors: [Color] = [.orange, .red, .purple, .pink, .green, .blue]

    var body: some View {
        @Bindable var viewModel = viewModel
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                // HEADER
                HStack {
                    Circle().fill(.gray.opacity(0.3)).frame(width: 50, height: 50)
                        .overlay(Image(systemName: "person.fill").foregroundColor(.white))
                    Text("Welcome Back!").font(.title3).fontWeight(.bold).foregroundColor(.blue)
                    Spacer()
                    HStack(spacing: 5) {
                        Text("🔥 \(viewModel.streakCount)")
                        Image(systemName: "heart").foregroundColor(.blue)
                    }
                }
                .padding(.horizontal).padding(.top, 20)
               
                // SUBJECTS HEADER
                HStack {
                    Text("Subjects").font(.headline).foregroundColor(.blue)
                    Spacer()
                    NavigationLink(destination: SubjectPickerView()) {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundColor(.blue)
                    }
                }
                .padding(.horizontal).padding(.top, 30)

                // SUBJECT CARDS
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 15) {
                        ForEach(Array(viewModel.chosenSubjects.enumerated()), id: \.offset) { index, subject in
                            SubjectCard(title: subject, color: cardColors[index % cardColors.count])
                        }
                    }
                    .padding(.horizontal).padding(.top, 15)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            CustomNavBar(selectedTab: 0)
        }
        .navigationBarBackButtonHidden(true)
        // THE MODAL POP-UP LOGIC
        .sheet(isPresented: $viewModel.showCreateSheet) {
            CreateResourceView()
                .presentationDetents([.medium]) // Half-height pop-up
                .presentationDragIndicator(.visible) // The "grabber" handle
        }
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
            Image(systemName: "brain.head.profile")
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
    NavigationStack {
        HomeView()
            .environment(AppViewModel())
    }
}
