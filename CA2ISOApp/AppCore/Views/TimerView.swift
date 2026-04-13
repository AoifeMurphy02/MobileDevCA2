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
        // Global Pop-up sheet
        .sheet(isPresented: $viewModel.showCreateSheet) {
            CreateResourceView().presentationDetents([.medium])
        }
    }
}

#Preview {
    NavigationStack {
        TimerView().environment(AppViewModel())
    }
}
