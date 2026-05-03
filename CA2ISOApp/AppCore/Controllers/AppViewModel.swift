//
//  AppViewModel.swift
//  CA2ISOApp
//
//  Created by Aoife on 24/03/2026.
//
import Foundation
import Observation
import SwiftData
import SwiftUI
import AuthenticationServices
import GoogleSignIn


// Define the possible screens for navigation
enum NavTarget: Hashable {
    case signup
    case login
    case home
    case studySubjectPicker
    case flashcards
    case flashcardReview
    case studyGuide
    case practiceTests
    case timer
    case createFlashcardsManually
    case flashcardSetDetail(FlashcardSet)
}

@Observable
class AppViewModel {
    
    var navPath = NavigationPath()
    
    var email = ""
    var password = ""
    var hasAgreedToTerms = false
    
    var isLoggedIn = false // New state to trigger navigation to Home
    var loginError = ""    // For error handling
    
    var chosenstudySubjects: [String] = []
    var activestudySubject = ""
    var currentUserEmail: String?
    //hardcoded for now
    var streakCount: Int = 2
    
    
    // was sign up successful if so we move screens
    var isSignedUp = false
    
    // Logic to control the pop-up sheet
    var showCreateSheet = false
    
    var flashcardDraftTitle = ""
    var flashcardDraftSourceType = ""
    var flashcardDraftstudySubject = ""
    var flashcardDraftTopic = ""
    var flashcardDraftRawText = ""
    var flashcardDraftAIGenerationMode = ""
    var flashcardDraftAIModelID = ""
    var flashcardDraftCards: [FlashcardDraft] = []
    
    
    var pendingNavigation: NavTarget? = nil

    var hasFlashcardDraft: Bool {
        !flashcardDraftCards.isEmpty
    }

    var studySubjectOptions: [String] {
        uniquestudySubjects(from: chosenstudySubjects)
    }

    var defaultstudySubjectForCreation: String {
        if !activestudySubject.isEmpty {
            return activestudySubject
        }

        return studySubjectOptions.first ?? ""
    }
    
    //  save the user
    func signUpUser(modelContext: ModelContext) {
        guard !email.isEmpty, !password.isEmpty, hasAgreedToTerms else {
            print("Error: Missing information")
            return
        }

        loginError = ""
        
        // Clean the email before saving
        let cleanEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let newUser = User(email: cleanEmail, password: password)
        
        // Insert into memory
        modelContext.insert(newUser)
        
        // FORCE save to the phone's disk
        do {
            
            try modelContext.save()
            self.currentUserEmail = cleanEmail // Set the session immediately
            applyChosenstudySubjects([])
            print("SUCCESS: User \(cleanEmail) saved to SwiftData!")
            
            // 3. Double Check: Verify the save worked right now
            let descriptor = FetchDescriptor<User>()
            let count = (try? modelContext.fetchCount(descriptor)) ?? 0
            print("DEBUG: Total users now in database: \(count)")
            
            // Trigger navigation
            isSignedUp = true
        } catch {
            print("CRITICAL ERROR: Could not save to disk: \(error.localizedDescription)")
        }
    }
    
    
    // searches SwiftData for a matching user
    func loginUser(users: [User]) {
        print("Users found in database: \(users.count)")
        loginError = ""
        
        let cleanEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        print("Searching for cleaned email: [\(cleanEmail)]")
        
        if let foundUser = users.first(where: { $0.email.lowercased() == cleanEmail }) {
            if foundUser.password == password {
                self.currentUserEmail = foundUser.email // Remember the user
                applyChosenstudySubjects(foundUser.savedstudySubjects)
                self.isLoggedIn = true
            }
            else {
                //print("ERROR: Password typed [\(password)] does not match saved [\(foundUser.password)]")
                self.loginError = "Wrong password."
            }
        } else {
            //print("ERROR: No user found with email [\(cleanEmail)]")
            self.loginError = "User not found."
        }
    }
    
    //Save the studySubjects to the Database
    func persiststudySubjectsToDatabase(modelContext: ModelContext, users: [User]) {
        // Clean the session email to match the database format
        guard let sessionEmail = currentUserEmail?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else {
            print("DEBUG: No user email found in session. Cannot save.")
            return
        }
        
        // Find the user in the database (using case-insensitive check)
        if let userInDB = users.first(where: { $0.email.lowercased() == sessionEmail }) {
            
            // Sync the data
            userInDB.savedstudySubjects = self.studySubjectOptions
            
            do {
                // Force SwiftData to write the change to the disk
                try modelContext.save()
                print("SUCCESS: Saved \(self.studySubjectOptions.count) studySubjects for user: \(sessionEmail)")
            } catch {
                print("ERROR: Could not save to database: \(error.localizedDescription)")
            }
        } else {
            print("DEBUG: Could not find user [\(sessionEmail)] in database. Total users: \(users.count)")
        }
    }
    func loadFlashcardDraft(_ draft: FlashcardDeckDraft) {
        flashcardDraftTitle = draft.title
        flashcardDraftSourceType = draft.sourceType
        flashcardDraftstudySubject = draft.studySubject.isEmpty ? defaultstudySubjectForCreation : draft.studySubject
        flashcardDraftTopic = draft.topic
        flashcardDraftRawText = draft.rawText
        flashcardDraftAIGenerationMode = draft.aiGenerationMode
        flashcardDraftAIModelID = draft.aiModelID
        flashcardDraftCards = draft.cards
        self.flashcardDraftCards = draft.cards 
    }

    func clearFlashcardDraft() {
        StudyNotificationManager.cancelDraftReviewReminder()
        flashcardDraftTitle = ""
        flashcardDraftSourceType = ""
        flashcardDraftstudySubject = ""
        flashcardDraftTopic = ""
        flashcardDraftRawText = ""
        flashcardDraftAIGenerationMode = ""
        flashcardDraftAIModelID = ""
        flashcardDraftCards = []
    }

    func addEmptyFlashcardDraft(style: FlashcardPromptStyle = .summary) {
        flashcardDraftCards.append(
            FlashcardDraft(
                question: "",
                answer: "",
                style: style
            )
        )
    }

    func applyChosenstudySubjects(_ studySubjects: [String]) {
        chosenstudySubjects = uniquestudySubjects(from: studySubjects)

        if !activestudySubject.isEmpty, chosenstudySubjects.contains(activestudySubject) {
            return
        }

        activestudySubject = chosenstudySubjects.first ?? ""
    }

    func selectstudySubject(_ studySubject: String) {
        activestudySubject = studySubject
    }

    private func uniquestudySubjects(from studySubjects: [String]) -> [String] {
        var seen = Set<String>()
        var orderedstudySubjects: [String] = []

        for studySubject in studySubjects {
            let normalizedstudySubject = studySubject.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedstudySubject.isEmpty, !seen.contains(normalizedstudySubject) else { continue }

            seen.insert(normalizedstudySubject)
            orderedstudySubjects.append(normalizedstudySubject)
        }

        return orderedstudySubjects
    }
        
        //  fix to demo due to no Xcode Capability
        func mockAppleSignIn(modelContext: ModelContext) {
            let mockEmail = "aoife_apple@demo.ie"
            print("DEBUG: Executing Apple Sign-In Bypass for \(mockEmail)")
            
            self.currentUserEmail = mockEmail
           
            
          
            let newUser = User(email: mockEmail, appleUserID: "mock_id_12345")
            modelContext.insert(newUser)
            
            // moves the screen
            DispatchQueue.main.async {
                self.isLoggedIn = true
                self.isSignedUp = true
            }
        }

        // real apple login 
        func handleAppleSignIn(result: Result<ASAuthorization, Error>, modelContext: ModelContext) {
            switch result {
            case .success(let auth):
                if let appleIDCredential = auth.credential as? ASAuthorizationAppleIDCredential {
                    let userId = appleIDCredential.user
                    let email = appleIDCredential.email ?? "AppleUser@test.com"
                    
                    self.currentUserEmail = email
                    let newUser = User(email: email, appleUserID: userId)
                    modelContext.insert(newUser)
                    
                    DispatchQueue.main.async {
                        self.isLoggedIn = true
                        self.isSignedUp = true
                    }
                }
            case .failure(let error):
                print("Apple Auth failed: \(error.localizedDescription)")
                self.loginError = "Sign in with Apple failed."
            }
        }
    
    func configureGoogleSignIn() {
        let config = GIDConfiguration(clientID: "246535979151-p94puseklqtr84m06go44e96bf354go8.apps.googleusercontent.com")
        GIDSignIn.sharedInstance.configuration = config
    }
    
    func handleGoogleSignIn(modelContext: ModelContext) {
        // Find the active window scene to get the root view controller
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        let window = windowScene?.windows.first { $0.isKeyWindow }
        
        guard let rootVC = window?.rootViewController else {
            print("DEBUG: Could not find root view controller")
            return
        }
        
        // 2. Start the Google Sign In
        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            if let error = error {
                print("Google Login Error: \(error.localizedDescription)")
                return
            }
            
            guard let user = result?.user else { return }
            
            let email = user.profile?.email ?? ""
            
            self.currentUserEmail = email
            
            let newUser = User(email: email, googleUserID: user.userID)
            modelContext.insert(newUser)
            
            DispatchQueue.main.async {
                self.isLoggedIn = true
            }
        }
    }
    func recordStudyActivity(modelContext: ModelContext, users: [User]) {
        guard let email = currentUserEmail else { return }
        
        // 1. Find the logged-in user in the database
        if let user = users.first(where: { $0.email.lowercased() == email.lowercased() }) {
            let calendar = Calendar.current
            let now = Date.now
            
            // 2. Prevent double-counting today
            if let lastDate = user.lastActivityDate, calendar.isDateInToday(lastDate) {
                print("Streak: Already recorded for today.")
                self.streakCount = user.streakCount
                return
            }
            
            // 3. Logic: Consecutive days or Reset?
            if let lastDate = user.lastActivityDate, calendar.isDateInYesterday(lastDate) {
                user.streakCount += 1
            } else {
                // First time ever OR they missed a day
                user.streakCount = 1
            }
            
            // 4. Update the Database and the UI
            user.lastActivityDate = now
            self.streakCount = user.streakCount
            
            try? modelContext.save()
            print("SUCCESS: Streak is now \(self.streakCount)")
        }
    }
}
