import Foundation
import Observation

@Observable
class TimerViewModel {
    
    
    var timeRemaining = 1500 // 25 minutes
    private var selectedDurationSeconds = 1500
    var isActive = false
    var timer: Timer?
    var hasFinishedSession = false
    
    func formatTime() -> String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    func toggleTimer() {
        if isActive {
            timer?.invalidate()
            StudyNotificationManager.cancelTimerComplete()
        } else {
            StudyNotificationManager.scheduleTimerComplete(after: TimeInterval(timeRemaining))
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                if self.timeRemaining > 0 {
                    self.timeRemaining -= 1
                } else {
                    self.timerFinished()
                }
            }
        }
        isActive.toggle()
    }
    
    func resetTimer() {
        timer?.invalidate()
        StudyNotificationManager.cancelTimerComplete()
        isActive = false
        timeRemaining = selectedDurationSeconds
    }
    
   // func timerFinished() {
     //   timer?.invalidate()
       // isActive = false
    //}
    func timerFinished() {
            timer?.invalidate()
            isActive = false
            timeRemaining = 0
            //sendNotification()
            
            // TRIGGER THE CHANGE:
            self.hasFinishedSession = true
        }
    func setDuration(minutes: Int) {
        // Stop any running timer
        timer?.invalidate()
        StudyNotificationManager.cancelTimerComplete()
        isActive = false
        
        // Set the new time (Minutes * 60 seconds)
        selectedDurationSeconds = minutes * 60
        timeRemaining = selectedDurationSeconds
    }

}
