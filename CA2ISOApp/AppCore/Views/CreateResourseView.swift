//
//  CreateResourseView.swift
//  CA2ISOApp
//
//  Created by Aoife on 03/04/2026.
//

import Foundation

import SwiftUI

struct CreateResourceView: View {
    @Environment(AppViewModel.self) private var viewModel
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.gray.opacity(0.1).ignoresSafeArea()
            
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 6)
                    .padding(.top, 15)
                
                VStack(spacing: 25) {
                    //Buttons with navigation logic
                    ResourceActionButton(title: "Create Flashcards Set", icon: "doc.on.doc.fill", iconColor: .cyan) {
                        viewModel.activeNavigation = .flashcards
                        viewModel.showCreateSheet = false
                    }
                    
                    ResourceActionButton(title: "Create Study Guide", icon: "book.pages.fill", iconColor: .purple) {
                        viewModel.activeNavigation = .studyGuide
                        viewModel.showCreateSheet = false
                    }
                    
                    ResourceActionButton(title: "Create Practice Tests", icon: "checklist", iconColor: .green) {
                        viewModel.activeNavigation = .practiceTests
                        viewModel.showCreateSheet = false
                    }
                }
                .padding(.top, 40)
                .padding(.horizontal, 30)
                
                Spacer()
                CustomNavBar(selectedTab: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: UIScreen.main.bounds.height * 0.55)
            .background(Color.white)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40))
        }
        .navigationBarBackButtonHidden(true)
        .ignoresSafeArea(edges: .bottom)
    }
}

//  Update the button component to accept an action
struct ResourceActionButton: View {
    var title: String
    var icon: String
    var iconColor: Color
    var action: () -> Void 
    
    var body: some View {
        Button(action: action) { // Triggers the navigation logic
            HStack(spacing: 20) {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundColor(iconColor)
                    .frame(width: 60, height: 60)
                    .background(iconColor.opacity(0.1))
                    .cornerRadius(12)
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(.black)
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 15).stroke(Color.blue.opacity(0.2), lineWidth: 2))
            .background(Color.white)
            .cornerRadius(15)
        }
    }
}

#Preview {
    NavigationStack {
        CreateResourceView()
            .environment(AppViewModel())
    }
}

