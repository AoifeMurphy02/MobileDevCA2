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
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.1) 
            
            HStack {
                Spacer()
                
                Button(action: {
                    viewModel.navPath = NavigationPath()
                                        viewModel.navPath.append(NavTarget.home)
                                        viewModel.showCreateSheet = false
                    
                }) {
                    
                    NavBarIcon(iconName: "house", isSelected: selectedTab == 0)
                }
                
                
                Spacer()
                
                // add
                Button(action: {
                                    // This triggers the pop-up sheet on the HomeView
                                    viewModel.showCreateSheet = true
                                }) {
                                    ZStack {
                                        // Shows the blue circle if we are currently on the "Add" state
                                        if selectedTab == 1 {
                                            Circle()
                                                .fill(Color.blue.opacity(0.3))
                                                .frame(width: 50, height: 50)
                                        }
                                        
                                        Image(systemName: "plus")
                                            .font(.title2)
                                            .foregroundColor(.black)
                                    }
                                }
                
                Spacer()
                
                // clock
                
                Button(action: {
                    viewModel.navPath.append(NavTarget.timer)
                    viewModel.showCreateSheet = false
                }) {
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
