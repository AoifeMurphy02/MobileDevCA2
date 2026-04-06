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
            
            // Pop up Container
            VStack(spacing: 0) {
                // Top "Grabber" Handle
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 6)
                    .padding(.top, 15)
                
                VStack(spacing: 25) {
                    // Button list
                    ResourceActionButton(
                        title: "Create Flashcards Set",
                        icon: "doc.on.doc.fill",
                        iconColor: .cyan
                    )
                    
                    ResourceActionButton(
                        title: "Create Study Guide",
                        icon: "book.pages.fill",
                        iconColor: .purple
                    )
                    
                    ResourceActionButton(
                        title: "Create Practice Tests",
                        icon: "checklist",
                        iconColor: .green
                    )
                }
                .padding(.top, 40)
                .padding(.horizontal, 30)
                
                Spacer()
                
                // Nav Bar at the  bottom
                CustomNavBar(selectedTab: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: UIScreen.main.bounds.height * 0.55) // Height is 55% of screen
            .background(Color.white)
            
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40))
            .overlay(
               
                UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40)
                    .stroke(Color.blue.opacity(0.1), lineWidth: 1)
            )
        }
        .navigationBarBackButtonHidden(true)
        .ignoresSafeArea(edges: .bottom)
    }
}

// Reusable Button Component
struct ResourceActionButton: View {
    var title: String
    var icon: String
    var iconColor: Color
    
    var body: some View {
        Button(action: {
            print("\(title) tapped")
        }) {
            HStack(spacing: 20) {
                // icon container
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
            .frame(maxWidth: .infinity)
          
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 2)
            )
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

