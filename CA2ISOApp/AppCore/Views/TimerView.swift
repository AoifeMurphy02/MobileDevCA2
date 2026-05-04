import SwiftUI
import SwiftData

struct TimerView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    
    @State private var timerVM = TimerViewModel()
    @State private var showTimePicker = false
    @State private var selectedMinutes = 25
    
    var body: some View {
        //@Bindable var bindableVM = viewModel
        let showCreateSheet = Binding(
                    get: { viewModel.showCreateSheet },
                    set: { viewModel.showCreateSheet = $0 }
                )
        
        ZStack(alignment: .bottom) {
            VStack(spacing: 40) {
                Spacer()
                
                VStack(spacing: 5) {
                    Text(timerVM.formatTime())
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .onTapGesture {
                            if !timerVM.isActive { showTimePicker = true }
                        }
                    
                    if !timerVM.isActive {
                        Text("Tap to set time").font(.caption).foregroundColor(.gray)
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
                
                Button(action: { timerVM.toggleTimer() }) {
                    Image(systemName: timerVM.isActive ? "pause.fill" : "play.fill")
                        .font(.system(size: 40)).foregroundColor(.black).padding()
                }
                
                Spacer(); Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            
            CustomNavBar(selectedTab: 2)
        }
        .navigationBarBackButtonHidden(true)
        .enableSwipeBack()
        
        .onChange(of: timerVM.hasFinishedSession) { oldValue, newValue in
                  if newValue == true {
                      print("DEBUG: View detected timer finished. Updating streak...")
                      viewModel.recordStudyActivity(modelContext: modelContext)
                      
                      // Reset the trigger so it can happen again next time
                      timerVM.hasFinishedSession = false
                  }
              }
        
        .sheet(isPresented: $showTimePicker) {
            VStack(spacing: 20) {
                Text("Set Study Duration").font(.headline).padding(.top)
                Picker("Minutes", selection: $selectedMinutes) {
                    ForEach(1...60, id: \.self) { Text("\($0) minutes").tag($0) }
                }
                .pickerStyle(.wheel)
                Button("Set Timer") {
                    timerVM.setDuration(minutes: selectedMinutes)
                    showTimePicker = false
                }
                .padding().background(Color.blue).foregroundColor(.white).clipShape(Capsule()).padding()
            }
            .presentationDetents([.height(300)])
        }
        

        .sheet(isPresented: showCreateSheet) {
                   CreateResourceView().presentationDetents([.medium])
               }
        
       }
        
    }
