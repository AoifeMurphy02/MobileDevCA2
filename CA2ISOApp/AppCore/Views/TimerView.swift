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
                        Label("Tap the time to change duration", systemImage: "hand.tap.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppTheme.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(AppTheme.primary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                
                Image("owl_mascot")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 220, height: 220)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 42, style: .continuous)
                            .stroke(AppTheme.subtleBorder, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 14, y: 7)
                    .onLongPressGesture {
                        timerVM.resetTimer()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                
                HStack(spacing: 18) {
                    Button(action: {
                        timerVM.resetTimer()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.headline)
                            .foregroundColor(AppTheme.secondaryText)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .background(AppTheme.secondarySurface)
                            .clipShape(Capsule())
                    }

                    Button(action: { timerVM.toggleTimer() }) {
                        Image(systemName: timerVM.isActive ? "pause.fill" : "play.fill")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 76, height: 76)
                            .background(AppTheme.primary)
                            .clipShape(Circle())
                            .shadow(color: AppTheme.primary.opacity(0.30), radius: 14, y: 7)
                    }
                }
                .buttonStyle(.plain)
                
                Spacer(); Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background)
            
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
