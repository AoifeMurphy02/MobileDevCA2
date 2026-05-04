//
//  CreatePracticeTestView.swift
//  CA2ISOApp
//
//  Created by Aoife on 06/04/2026.
//

import Foundation
import SwiftUI

import SwiftUI

struct CreatePracticeTestView: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 15) {
                    // Profile Image
                    Circle()
                        .fill(.gray.opacity(0.3))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.white)
                        )
                        .clipShape(Circle())
                    
                    Text("Create Practice Test")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.11, green: 0.49, blue: 0.95))
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 20)
               
              
                VStack(spacing: 20) {
                    TestActionButton(icon: "doc.on.doc", title: "Paste Text")
                    TestActionButton(icon: "paperclip", title: "Select file")
                    TestActionButton(icon: "square.stack.3d.up.fill", title: "Flashcard Set")
                }
                .padding(.horizontal, 25)
                .padding(.top, 40)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppTheme.surface)

            // NAV BAR
            CustomNavBar(selectedTab: 1) // Plus tab is active
        }
        .navigationBarBackButtonHidden(true)
        .enableSwipeBack()
    }
}

struct TestActionButton: View {
    var icon: String
    var title: String
    
    var body: some View {
        Button(action: {
            print("\(title) tapped")
        }) {
            HStack(spacing: 15) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                
                Spacer()
            }
            .foregroundColor(AppTheme.text)
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            // THE STYLING: Blue border with rounded corners
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.4), lineWidth: 1.5)
            )
            .background(AppTheme.surface)
            .cornerRadius(12)
        }
    }
}

#Preview {
    NavigationStack {
        CreatePracticeTestView()
            .environment(AppViewModel())
    }
}
