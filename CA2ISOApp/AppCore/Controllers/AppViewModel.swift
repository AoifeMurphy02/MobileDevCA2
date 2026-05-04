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
import GoogleSignIn


// Define the possible screens for navigation
enum NavTarget: Hashable {
    case signup
    case login
    case home
    case studyAreaPicker
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
    private nonisolated static let persistedEmailKey = "auth.persisted.email"
    private nonisolated static let persistedGoogleUserIDKey = "auth.persisted.googleUserID"
    private nonisolated static let shouldRestoreSessionKey = "auth.persisted.shouldRestore"
    
    var navPath = NavigationPath()
    
    var email = ""
    var password = ""
    var hasAgreedToTerms = false
    
    var isLoggedIn = false // New state to trigger navigation to Home
    var loginError = ""    // For error handling
    
    var chosenstudyAreas: [String] = []
    var activestudyArea = ""
    var currentUserEmail: String?
    var rememberMePreference = UserDefaults.standard.bool(forKey: shouldRestoreSessionKey)
    //hardcoded for now
    var streakCount: Int = 2
    
    
    // was sign up successful if so we move screens
    var isSignedUp = false
    
    // Logic to control the pop-up sheet
    var showCreateSheet = false
    
    var flashcardDraftTitle = ""
    var flashcardDraftSourceType = ""
    var flashcardDraftstudyArea = ""
    var flashcardDraftTopic = ""
    var flashcardDraftRawText = ""
    var flashcardDraftAIGenerationMode = ""
    var flashcardDraftAIModelID = ""
    var flashcardDraftCards: [FlashcardDraft] = []
    
    
    var pendingNavigation: NavTarget? = nil
    private var didAttemptSessionRestore = false

    var hasFlashcardDraft: Bool {
        !flashcardDraftCards.isEmpty
    }

    var studyAreaOptions: [String] {
        uniquestudyAreas(from: chosenstudyAreas)
    }

    var defaultstudyAreaForCreation: String {
        if !activestudyArea.isEmpty {
            return activestudyArea
        }

        return studyAreaOptions.first ?? ""
    }
    
    //  save the user
    func signUpUser(modelContext: ModelContext) {
        let cleanEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanEmail.isEmpty else {
            loginError = "Please enter your email."
            return
        }

        guard !trimmedPassword.isEmpty else {
            loginError = "Please enter your password."
            return
        }

        guard hasAgreedToTerms else {
            loginError = "Please accept the Terms & Conditions before signing up."
            return
        }

        loginError = ""

        let existingUsers = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        if existingUsers.contains(where: { $0.email.lowercased() == cleanEmail }) {
            loginError = "An account with this email already exists."
            return
        }

        let newUser = User(email: cleanEmail, password: trimmedPassword)
        
        // Insert into memory
        modelContext.insert(newUser)
        
        // FORCE save to the phone's disk
        do {
            
            try modelContext.save()
            completeAuthenticatedSession(for: newUser, shouldRestoreSession: true)
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
    func loginUser(users: [User], rememberSession: Bool) {
        print("Users found in database: \(users.count)")
        loginError = ""
        rememberMePreference = rememberSession
        
        let cleanEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        print("Searching for cleaned email: [\(cleanEmail)]")

        guard !cleanEmail.isEmpty else {
            self.loginError = "Please enter your email."
            return
        }

        guard !trimmedPassword.isEmpty else {
            self.loginError = "Please enter your password."
            return
        }
        
        if let foundUser = users.first(where: { $0.email.lowercased() == cleanEmail }) {
            if foundUser.password == trimmedPassword {
                completeAuthenticatedSession(for: foundUser, shouldRestoreSession: rememberSession)
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
    
    //Save the studyAreas to the Database
    func persiststudyAreasToDatabase(modelContext: ModelContext, users: [User]) {
        // Clean the session email to match the database format
        guard let sessionEmail = currentUserEmail?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else {
            print("DEBUG: No user email found in session. Cannot save.")
            return
        }
        
        // Find the user in the database (using case-insensitive check)
        if let userInDB = users.first(where: { $0.email.lowercased() == sessionEmail }) {
            
            // Sync the data
            userInDB.savedstudyAreas = self.studyAreaOptions
            
            do {
                // Force SwiftData to write the change to the disk
                try modelContext.save()
                print("SUCCESS: Saved \(self.studyAreaOptions.count) studyAreas for user: \(sessionEmail)")
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
        flashcardDraftstudyArea = draft.studyArea.isEmpty ? defaultstudyAreaForCreation : draft.studyArea
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
        flashcardDraftstudyArea = ""
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

    func applyChosenstudyAreas(_ name: [String]) {
        chosenstudyAreas = uniquestudyAreas(from: name)

        if !activestudyArea.isEmpty, chosenstudyAreas.contains(activestudyArea) {
            return
        }

        activestudyArea = chosenstudyAreas.first ?? ""
    }

    func selectstudyArea(_ name: String) {
        activestudyArea = name
    }

    private func uniquestudyAreas(from studyAreas: [String]) -> [String] {
        var seen = Set<String>()
        var orderedstudyAreas: [String] = []

        for studyArea in studyAreas {
            let normalizedstudyArea = studyArea.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedstudyArea.isEmpty, !seen.contains(normalizedstudyArea) else { continue }

            seen.insert(normalizedstudyArea)
            orderedstudyAreas.append(normalizedstudyArea)
        }

        return orderedstudyAreas
    }

    func restorePersistedSession(users: [User]) -> NavTarget? {
        guard UserDefaults.standard.bool(forKey: Self.shouldRestoreSessionKey) else {
            didAttemptSessionRestore = true
            return nil
        }

        guard !didAttemptSessionRestore else { return nil }

        if users.isEmpty {
            return nil
        }

        didAttemptSessionRestore = true

        guard let user = restoredUser(from: users) else {
            clearPersistedSession()
            return nil
        }

        completeAuthenticatedSession(for: user, shouldRestoreSession: true)
        return user.savedstudyAreas.isEmpty ? .studyAreaPicker : .home
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
                self.loginError = "Google sign-in failed."
                return
            }
            
            guard let user = result?.user else { return }
            
            let email = user.profile?.email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let existingUsers = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
            let matchedUser = existingUsers.first {
                $0.googleUserID == user.userID || (!email.isEmpty && $0.email.lowercased() == email)
            } ?? User(email: email, googleUserID: user.userID)

            if matchedUser.modelContext == nil {
                modelContext.insert(matchedUser)
            }

            matchedUser.googleUserID = user.userID

            do {
                try modelContext.save()
                self.completeAuthenticatedSession(for: matchedUser, shouldRestoreSession: true)

                DispatchQueue.main.async {
                    self.isLoggedIn = true
                }
            } catch {
                self.loginError = "Could not finish Google sign-in."
            }
        }
    }
    func recordStudyActivity(modelContext: ModelContext, users: [User]) {
        guard let email = currentUserEmail?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else {
            return
        }

        if let user = users.first(where: { $0.email.lowercased() == email }) {
            let calendar = Calendar.current
            let now = Date.now

            if let lastDate = user.lastActivityDate, calendar.isDateInToday(lastDate) {
                self.streakCount = user.streakCount
                return
            }

            if let lastDate = user.lastActivityDate, calendar.isDateInYesterday(lastDate) {
                user.streakCount += 1
            } else {
                user.streakCount = 1
            }

            user.lastActivityDate = now
            self.streakCount = user.streakCount

            try? modelContext.save()
            print("DEBUG: Streak updated to \(self.streakCount) for \(email)")
        }
    }

    func goHome() {
        var path = NavigationPath()
        path.append(NavTarget.home)
        self.navPath = path
    }

    private func completeAuthenticatedSession(for user: User, shouldRestoreSession: Bool) {
        currentUserEmail = user.email
        applyChosenstudyAreas(user.savedstudyAreas)
        rememberMePreference = shouldRestoreSession
        loginError = ""

        if shouldRestoreSession {
            persistSession(for: user)
        } else {
            clearPersistedSession()
        }
    }

    private func persistSession(for user: User) {
        let defaults = UserDefaults.standard
        defaults.set(user.email, forKey: Self.persistedEmailKey)
        defaults.set(user.googleUserID, forKey: Self.persistedGoogleUserIDKey)
        defaults.set(true, forKey: Self.shouldRestoreSessionKey)
    }

    private func clearPersistedSession() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.persistedEmailKey)
        defaults.removeObject(forKey: Self.persistedGoogleUserIDKey)
        defaults.set(false, forKey: Self.shouldRestoreSessionKey)
    }

    private func restoredUser(from users: [User]) -> User? {
        let defaults = UserDefaults.standard
        let persistedGoogleUserID = defaults.string(forKey: Self.persistedGoogleUserIDKey)
        let persistedEmail = defaults.string(forKey: Self.persistedEmailKey)?
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let persistedGoogleUserID,
           let matchedUser = users.first(where: { $0.googleUserID == persistedGoogleUserID }) {
            return matchedUser
        }

        guard let persistedEmail else {
            return nil
        }

        return users.first { $0.email.lowercased() == persistedEmail }
    }
}
