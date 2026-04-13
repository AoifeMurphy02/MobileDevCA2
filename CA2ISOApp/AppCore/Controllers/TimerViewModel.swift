import Foundation
import Observation
import UserNotifications

@Observable
class TimerViewModel {
    var timeRemaining = 1500 // 25 minutes
    var isActive = false
    var timer: Timer?
    
    func formatTime() -> String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    func toggleTimer() {
        if isActive {
            timer?.invalidate()
        } else {
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
        isActive = false
        timeRemaining = 1500
    }
    
    func timerFinished() {
        timer?.invalidate()
        isActive = false
        sendNotification()
    }

    func sendNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Study Session Complete!"
        content.body = "Great job focusing. Take a short break!"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
