import SwiftUI
import SwiftData

struct TimerView: View {
    
    
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @Query var allUsers: [User]
    @State private var timerVM = TimerViewModel()
    
    @State private var showTimePicker = false
    @State private var selectedMinutes = 25 // Default value for the picker
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 40) {
                Spacer()
                
                VStack(spacing: 5) {
                    Text(timerVM.formatTime())
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .onTapGesture {
                            // Only allow changing time if timer isn't running
                            if !timerVM.isActive {
                                showTimePicker = true
                            }
                        }
                    
                    if !timerVM.isActive {
                        Text("Tap to set time")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                
                Image("owl_mascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 250)
                    .onLongPressGesture {
                        timerVM.resetTimer()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                
                // PLAY/PAUSE BUTTON
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
            
            // Reusable Nav Bar
            CustomNavBar(selectedTab: 2)
        }
        .navigationBarBackButtonHidden(true)
        .enableSwipeBack()
        .sheet(isPresented: $showTimePicker) {
            VStack(spacing: 20) {
                Text("Set Study Duration")
                    .font(.headline)
                    .padding(.top)
                
                Picker("Minutes", selection: $selectedMinutes) {
                    ForEach(1...60, id: \.self) { min in
                        Text("\(min) minutes").tag(min)
                    }
                }
                .pickerStyle(.wheel) // the iOS wheel look
                
                Button(action: {
                    timerVM.setDuration(minutes: selectedMinutes)
                    showTimePicker = false
                }) {
                    Text("Set Timer")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .presentationDetents([.height(300)]) // Small pop-up height
        }
        .onAppear {
            timerVM.onComplete = {
                print("DEBUG: Timer hit zero. Recording study activity...")
                viewModel.recordStudyActivity(modelContext: modelContext, users: allUsers)
            }
        }
    }
}

#Preview {
    NavigationStack {
        TimerView().environment(AppViewModel())
    }
}
