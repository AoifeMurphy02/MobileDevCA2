//
//  StudyNotificationManager.swift
//  CA2ISOApp
//
//  Created by Meghana on 01/05/2026.
//

import Foundation
import UserNotifications

enum StudyNotificationManager {
    private nonisolated static let timerCompleteIdentifier = "study.timer.complete"
    private nonisolated static let dailyReminderIdentifier = "study.daily.reminder"
    private nonisolated static let draftReviewIdentifier = "study.draft.review"
    private nonisolated static let lastStudyDateKey = "study.notifications.lastStudyDate"
    private nonisolated static let lastDeckTitleKey = "study.notifications.lastDeckTitle"
    private nonisolated static let laststudyAreaKey = "study.notifications.laststudyArea"
    private nonisolated static let reminderHour = 19

    nonisolated static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else {
                return
            }

            center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                print(granted ? "Notifications Allowed" : "Notifications Denied")
            }
        }
    }

    nonisolated static func scheduleTimerComplete(after timeInterval: TimeInterval) {
        guard timeInterval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Study Session Complete!"
        content.body = "Great job focusing. Take a short break!"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        addRequest(identifier: timerCompleteIdentifier, content: content, trigger: trigger)
    }

    nonisolated static func cancelTimerComplete() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [timerCompleteIdentifier])
    }

    nonisolated static func scheduleDraftReviewReminder(
        deckTitle: String,
        studyArea: String,
        cardCount: Int,
        after timeInterval: TimeInterval = 15 * 60
    ) {
        guard !deckTitle.isEmpty, cardCount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Finish reviewing \(deckTitle)"
        content.body = draftReviewBody(deckTitle: deckTitle, studyArea: studyArea, cardCount: cardCount)
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        addRequest(identifier: draftReviewIdentifier, content: content, trigger: trigger)
    }

    nonisolated static func cancelDraftReviewReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [draftReviewIdentifier])
    }

    nonisolated static func scheduleResumeStudy(
        deckID: String,
        deckTitle: String,
        studyArea: String,
        progressText: String,
        after timeInterval: TimeInterval = 20 * 60
    ) {
        guard !deckID.isEmpty, !deckTitle.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "Resume \(deckTitle)"
        content.body = progressText.isEmpty
            ? resumeFallbackBody(studyArea: studyArea)
            : progressText
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        addRequest(
            identifier: resumeStudyIdentifier(for: deckID),
            content: content,
            trigger: trigger
        )
    }

    nonisolated static func cancelResumeStudy(for deckID: String) {
        guard !deckID.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [resumeStudyIdentifier(for: deckID)]
        )
    }

    nonisolated static func scheduleReviewReminder(
        deckID: String,
        deckTitle: String,
        reviewCount: Int,
        after timeInterval: TimeInterval = 4 * 60 * 60
    ) {
        guard !deckID.isEmpty, !deckTitle.isEmpty, reviewCount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Review your tricky cards"
        content.body = reviewCount == 1
            ? "You left 1 card to review in \(deckTitle)."
            : "You left \(reviewCount) cards to review in \(deckTitle)."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        addRequest(
            identifier: reviewReminderIdentifier(for: deckID),
            content: content,
            trigger: trigger
        )
    }

    nonisolated static func cancelReviewReminder(for deckID: String) {
        guard !deckID.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [reviewReminderIdentifier(for: deckID)]
        )
    }

    nonisolated static func recordStudyActivity(deckTitle: String, studyArea: String) {
        let defaults = UserDefaults.standard
        defaults.set(Date(), forKey: lastStudyDateKey)
        defaults.set(deckTitle.trimmingCharacters(in: .whitespacesAndNewlines), forKey: lastDeckTitleKey)
        defaults.set(studyArea.trimmingCharacters(in: .whitespacesAndNewlines), forKey: laststudyAreaKey)
        refreshDailyStudyReminder()
    }

    nonisolated static func refreshDailyStudyReminder() {
        cancelDailyStudyReminder()

        let defaults = UserDefaults.standard
        guard let lastStudyDate = defaults.object(forKey: lastStudyDateKey) as? Date else {
            return
        }

        let deckTitle = defaults.string(forKey: lastDeckTitleKey) ?? ""
        let studyArea = defaults.string(forKey: laststudyAreaKey) ?? ""

        let content = UNMutableNotificationContent()
        content.title = "Keep your study streak going"
        content.body = dailyReminderBody(deckTitle: deckTitle, studyArea: studyArea)
        content.sound = .default

        guard let nextReminderDate = nextDailyReminderDate(from: lastStudyDate) else {
            return
        }

        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: nextReminderDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        addRequest(identifier: dailyReminderIdentifier, content: content, trigger: trigger)
    }

    nonisolated static func cancelDailyStudyReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [dailyReminderIdentifier])
    }

    private nonisolated static func addRequest(
        identifier: String,
        content: UNMutableNotificationContent,
        trigger: UNNotificationTrigger
    ) {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private nonisolated static func resumeStudyIdentifier(for deckID: String) -> String {
        "study.resume.\(deckID)"
    }

    private nonisolated static func reviewReminderIdentifier(for deckID: String) -> String {
        "study.review.\(deckID)"
    }

    private nonisolated static func resumeFallbackBody(studyArea: String) -> String {
        if studyArea.isEmpty {
            return "Jump back into your flashcard session while it is still fresh."
        }

        return "Jump back into your \(studyArea) flashcard session while it is still fresh."
    }

    private nonisolated static func dailyReminderBody(deckTitle: String, studyArea: String) -> String {
        if !studyArea.isEmpty {
            return "A short \(studyArea) review today can keep your progress moving."
        }

        if !deckTitle.isEmpty {
            return "Open \(deckTitle) for a quick review and keep your progress moving."
        }

        return "Take a few minutes to review your flashcards today."
    }

    private nonisolated static func draftReviewBody(deckTitle: String, studyArea: String, cardCount: Int) -> String {
        let deckSummary = cardCount == 1
            ? "1 card still needs review"
            : "\(cardCount) cards still need review"

        if !studyArea.isEmpty {
            return "\(deckSummary) in your \(studyArea) deck. Save it when you are ready to start studying."
        }

        return "\(deckSummary) in \(deckTitle). Save the deck when you are ready to start studying."
    }

    private nonisolated static func nextDailyReminderDate(from lastStudyDate: Date) -> Date? {
        let calendar = Calendar.current
        let now = Date()

        var todayReminderComponents = calendar.dateComponents([.year, .month, .day], from: now)
        todayReminderComponents.hour = reminderHour
        todayReminderComponents.minute = 0

        guard let todayReminderDate = calendar.date(from: todayReminderComponents) else {
            return nil
        }

        if calendar.isDate(lastStudyDate, inSameDayAs: now) || now >= todayReminderDate {
            return calendar.date(byAdding: .day, value: 1, to: todayReminderDate)
        }

        return todayReminderDate
    }
}
