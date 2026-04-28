//
//  CA2ISOAppApp.swift
//  CA2ISOApp
//
//  Created by Aoife on 24/03/2026.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct CA2ISOAppApp: App {
    @State private var viewModel = AppViewModel()

    //  Handle notifications while app is open
    class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .sound])
        }
    }
    
    let notifyDelegate = NotificationDelegate()

    init() {
        // 2. Request Permissions on launch
        viewModel.configureGoogleSignIn()
        let center = UNUserNotificationCenter.current()
        center.delegate = notifyDelegate
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            print(granted ? "Notifications Allowed" : "Notifications Denied")
        }
    }

    var body: some Scene {
        WindowGroup {
            @Bindable var viewModel = viewModel
            
            // THE GLOBAL NAVIGATION ENGINE
            NavigationStack(path: $viewModel.navPath) {
                StartView()
                    .navigationDestination(for: NavTarget.self) { target in
                        switch target {
                        case .signup: SignupView()
                        case .login: LoginView()
                        case .home: HomeView()
                        case .subjectPicker: SubjectPickerView()
                        case .flashcards: CreateFlashCardView()
                        case .flashcardReview: FlashcardReviewView()
                        case .studyGuide: CreateStudyGuideView()
                        case .practiceTests: CreatePracticeTestView()
                        case .timer: TimerView()
                        case .createFlashcardsManually: CreateFlashcardManualView()
                        }
                    }
            }
            .environment(viewModel)
            // THE GLOBAL POP-UP (Triggered by the + button)
            .sheet(isPresented: $viewModel.showCreateSheet) {
                CreateResourceView()
                    .presentationDetents([.medium])
            }
            //  Wait for sheet to close before sliding
            .onChange(of: viewModel.showCreateSheet) { oldValue, newValue in
                if newValue == false, let target = viewModel.pendingNavigation {
                    viewModel.pendingNavigation = nil
                    // Delay prevents the 'Snapshotting' freeze
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        viewModel.navPath.append(target)
                    }
                }
            }
            .environment(viewModel)
        }
        .modelContainer(for: [User.self, FlashcardSet.self, Flashcard.self])
    }
}
