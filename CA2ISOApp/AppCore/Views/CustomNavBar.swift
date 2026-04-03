//
//  CustomNavBar.swift
//  CA2ISOApp
//
//  Created by Aoife on 01/04/2026.
//

import Foundation
import SwiftUI

struct CustomNavBar: View {
    // This tells the bar which tab is currently selected
    // 0 = Home, 1 = Add, 2 = Clock
    var selectedTab: Int

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.1) // Subtle line to separate from content
            
            HStack {
                Spacer()
                
                // --- HOME BUTTON ---
                NavigationLink(destination: HomeView()) {
                    NavBarIcon(iconName: "house", isSelected: selectedTab == 0)
                }
                
                Spacer()
                
                // --- ADD BUTTON ---
                NavigationLink(destination: CreateResourceView()) {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundColor(.black)
                }
                
                Spacer()
                
                // --- CLOCK BUTTON ---
                // Replace 'Text("History")' with timer screen when ready
                // Inside CustomNavBar.swift
                NavigationLink(destination: TimerView()) {
                    NavBarIcon(iconName: "clock", isSelected: selectedTab == 2)
                }
                
                Spacer()
            }
            .frame(height: 60)
            .background(
                Color(red: 0.88, green: 0.94, blue: 1.0)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
    }
}

// Sub-view for the individual icons to keep the code clean
struct NavBarIcon: View {
    var iconName: String
    var isSelected: Bool
    
    var body: some View {
        ZStack {
            if isSelected {
                Capsule()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 60, height: 35)
            }
            
            Image(systemName: iconName)
                .font(.title3)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundColor(.black)
        }
    }
}
