//
//  TimerView.swift
//  CA2ISOApp
//
//  Created by Aoife on 01/04/2026.
//

import Foundation
import SwiftUI

struct TimerView: View {
    @State private var timerVM = TimerViewModel()
    @Environment(AppViewModel.self) private var viewModel
    
    var body: some View {
        
        @Bindable var viewModel = viewModel
        
        ZStack(alignment: .bottom) {
            VStack(spacing: 40) {
                Spacer()
                
                Text(timerVM.formatTime())
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                
                Image("owl_mascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 250)
                    .onLongPressGesture {
                        timerVM.resetTimer()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                
                Button(action: { timerVM.toggleTimer() }) {
                    Image(systemName: timerVM.isActive ? "pause.fill" : "play.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.black)
                        .padding()
                }
                
                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            
            // The reusable bar
            CustomNavBar(selectedTab: 2)
        }
        // Moves to Flashcards/Tests from the Timer screen
        .navigationDestination(item: $viewModel.activeNavigation) { target in
            switch target {
            case .flashcards:
                CreateFlashCardView()
            case .studyGuide:
                CreateStudyGuideView()
            case .practiceTests:
                CreatePracticeTestView()
            }
        }
        // Shows the Create New sheet on the Timer screen
        .sheet(isPresented: $viewModel.showCreateSheet) {
            CreateResourceView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Prevent navigation loops
            viewModel.activeNavigation = nil
            
            // Notification Permissions
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        }
    }
}


#Preview {
    NavigationStack {
        TimerView()
            .environment(AppViewModel())
    }
}
