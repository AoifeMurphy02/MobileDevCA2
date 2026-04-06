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
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 40) {
                Spacer()
                
               
                Text(timerVM.formatTime())
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                
              
                Image("owl_mascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 250)
                    // Gestures (Long Press to Reset)
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
            
            
            CustomNavBar(selectedTab: 2)
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Request notification permission when screen opens
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        }
    }
}

#Preview {
    TimerView()
}
