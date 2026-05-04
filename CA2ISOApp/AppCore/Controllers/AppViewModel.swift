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
    private nonisolated static let rememberCredentialsKey = "auth.remembered.credentials"
    private nonisolated static let rememberedEmailKey = "auth.remembered.email"
    
    var navPath = NavigationPath()
    
    var email = ""
    var password = ""
    var hasAgreedToTerms = false
    
    var isLoggedIn = false // New state to trigger navigation to Home
    var loginError = ""    // For error handling
    
    var chosenstudyAreas: [String] = []
    var activestudyArea = ""
    var currentUserEmail: String?
    var rememberMePreference = UserDefaults.standard.bool(forKey: rememberCredentialsKey)
    var streakCount: Int = 0
    
    
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

    var activeSessionEmailForUI: String? {
        currentSessionEmail() ?? persistedSessionEmail()
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

        let existingUsers = fetchUsers(in: modelContext)
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
            LocalAccountStore.upsert(from: newUser)
            completeAuthenticatedSession(for: newUser)
            print("SUCCESS: User \(cleanEmail) saved to SwiftData!")
            isSignedUp = false
            navigateAfterAuthentication(for: newUser)
        } catch {
            loginError = "Could not create your account right now."
            print("CRITICAL ERROR: Could not save to disk: \(error.localizedDescription)")
        }
    }
    
    
    // searches SwiftData for a matching user
    func loginUser(modelContext: ModelContext, rememberCredentials: Bool) {
        loginError = ""
        rememberMePreference = rememberCredentials
        
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
        
        let users = fetchUsers(in: modelContext)
        print("Users found in database: \(users.count)")

        if let foundUser = resolvedUser(forEmail: cleanEmail, in: modelContext, cachedUsers: users) {
            if foundUser.password == trimmedPassword {
                persistRememberedCredentials(
                    email: cleanEmail,
                    shouldRemember: rememberCredentials
                )
                completeAuthenticatedSession(for: foundUser)
                self.isLoggedIn = false
                navigateAfterAuthentication(for: foundUser)
            }
            else {
                self.loginError = "Wrong password."
            }
        } else {
            self.loginError = "User not found."
        }
    }
    
    //Save the studyAreas to the Database
    func persiststudyAreasToDatabase(modelContext: ModelContext) {
        guard let targetEmail = currentSessionEmail() ?? persistedSessionEmail() else {
            print("DEBUG: No user email found in session. Cannot save.")
            return
        }

        guard let userInDB = resolvedUser(forEmail: targetEmail, in: modelContext) else {
            LocalAccountStore.updateStudyAreas(self.studyAreaOptions, forEmail: targetEmail)
            print("DEBUG: Updated local studyAreas only for user: \(targetEmail)")
            return
        }

        userInDB.savedstudyAreas = self.studyAreaOptions

        do {
            try modelContext.save()
            LocalAccountStore.upsert(from: userInDB)
            print("SUCCESS: Saved \(self.studyAreaOptions.count) studyAreas for user: \(userInDB.email)")
        } catch {
            print("ERROR: Could not save to database: \(error.localizedDescription)")
        }
    }

    func loadRememberedCredentials() {
        let defaults = UserDefaults.standard
        rememberMePreference = defaults.bool(forKey: Self.rememberCredentialsKey)

        guard rememberMePreference else { return }

        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            email = defaults.string(forKey: Self.rememberedEmailKey) ?? ""
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

        if activestudyArea.isEmpty {
            return
        }

        if chosenstudyAreas.contains(activestudyArea) {
            return
        }

        activestudyArea = ""
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

    func restorePersistedSession(modelContext: ModelContext) -> NavTarget? {
        guard UserDefaults.standard.bool(forKey: Self.shouldRestoreSessionKey) else {
            didAttemptSessionRestore = true
            return nil
        }

        guard !didAttemptSessionRestore else { return nil }

        didAttemptSessionRestore = true

        guard let user = restoredOrHydratedUser(in: modelContext) else {
            clearPersistedSession()
            return nil
        }

        completeAuthenticatedSession(for: user)
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
            let existingUsers = self.fetchUsers(in: modelContext)
            let matchedUser = existingUsers.first {
                $0.googleUserID == user.userID || (!email.isEmpty && $0.email.lowercased() == email)
            } ?? User(email: email, googleUserID: user.userID)

            if matchedUser.modelContext == nil {
                modelContext.insert(matchedUser)
            }

            matchedUser.googleUserID = user.userID

            do {
                try modelContext.save()
                LocalAccountStore.upsert(from: matchedUser)
                self.completeAuthenticatedSession(for: matchedUser)

                DispatchQueue.main.async {
                    self.isLoggedIn = false
                    self.navigateAfterAuthentication(for: matchedUser)
                }
            } catch {
                self.loginError = "Could not finish Google sign-in."
            }
        }
    }
    func recordStudyActivity(modelContext: ModelContext) {
        guard let user = currentAuthenticatedUser(in: modelContext) else {
            return
        }

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
        LocalAccountStore.upsert(from: user)
        print("DEBUG: Streak updated to \(self.streakCount) for \(user.email)")
    }

    func goHome() {
        var path = NavigationPath()
        path.append(NavTarget.home)
        showCreateSheet = false
        pendingNavigation = nil
        self.navPath = path
    }

    func resolvedAuthenticatedEmail(modelContext: ModelContext) -> String {
        if let user = currentAuthenticatedUser(in: modelContext) {
            completeAuthenticatedSession(for: user)
            return normalizedEmail(user.email)
        }

        if let restoredUser = restoredOrHydratedUser(in: modelContext) {
            completeAuthenticatedSession(for: restoredUser)
            return normalizedEmail(restoredUser.email)
        }

        return currentSessionEmail() ?? persistedSessionEmail() ?? ""
    }

    func syncCurrentUserState(modelContext: ModelContext) {
        let users = fetchUsers(in: modelContext)
        guard !users.isEmpty else {
            return
        }

        guard let user = currentAuthenticatedUser(in: users) ?? restoredUser(from: users) else {
            currentUserEmail = nil
            chosenstudyAreas = []
            activestudyArea = ""
            streakCount = 0
            return
        }

        currentUserEmail = user.email
        applyChosenstudyAreas(user.savedstudyAreas)
        streakCount = user.streakCount
    }

    private func completeAuthenticatedSession(for user: User) {
        currentUserEmail = user.email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        applyChosenstudyAreas(user.savedstudyAreas)
        streakCount = user.streakCount
        loginError = ""
        persistSession(for: user)
    }

    private func persistSession(for user: User) {
        let defaults = UserDefaults.standard
        defaults.set(user.email, forKey: Self.persistedEmailKey)

        if let googleUserID = user.googleUserID, !googleUserID.isEmpty {
            defaults.set(googleUserID, forKey: Self.persistedGoogleUserIDKey)
        } else {
            defaults.removeObject(forKey: Self.persistedGoogleUserIDKey)
        }

        defaults.set(true, forKey: Self.shouldRestoreSessionKey)
    }

    private func normalizedEmail(_ email: String) -> String {
        email
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        let persistedEmail = persistedSessionEmail()

        if let persistedGoogleUserID,
           let matchedUser = users.first(where: { $0.googleUserID == persistedGoogleUserID }) {
            return matchedUser
        }

        guard let persistedEmail else {
            return nil
        }

        return users.first { $0.email.lowercased() == persistedEmail }
    }

    private func navigateAfterAuthentication(for user: User) {
        let destination: NavTarget = user.savedstudyAreas.isEmpty ? .studyAreaPicker : .home
        showCreateSheet = false
        pendingNavigation = nil
        navPath = NavigationPath()
        navPath.append(destination)
    }

    private func fetchUsers(in modelContext: ModelContext) -> [User] {
        (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
    }

    private func resolvedUser(forEmail email: String, in modelContext: ModelContext, cachedUsers: [User]? = nil) -> User? {
        let users = cachedUsers ?? fetchUsers(in: modelContext)

        if let existingUser = users.first(where: { $0.email.lowercased() == email }) {
            return existingUser
        }

        guard let storedAccount = LocalAccountStore.account(email: email) else {
            return nil
        }

        let restoredUser = User(
            email: storedAccount.email,
            password: storedAccount.password,
            googleUserID: storedAccount.googleUserID,
            savedstudyAreas: storedAccount.savedstudyAreas
        )
        restoredUser.streakCount = storedAccount.streakCount
        restoredUser.lastActivityDate = storedAccount.lastActivityDate

        modelContext.insert(restoredUser)
        try? modelContext.save()
        return restoredUser
    }

    private func currentAuthenticatedUser(in modelContext: ModelContext) -> User? {
        currentAuthenticatedUser(in: fetchUsers(in: modelContext))
    }

    private func currentAuthenticatedUser(in users: [User]) -> User? {
        guard let normalizedEmail = currentSessionEmail() else {
            return nil
        }

        return users.first { user in
            user.email.lowercased() == normalizedEmail
        }
    }

    private func persistRememberedCredentials(email: String, shouldRemember: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(shouldRemember, forKey: Self.rememberCredentialsKey)

        if shouldRemember {
            defaults.set(email, forKey: Self.rememberedEmailKey)
        } else {
            defaults.removeObject(forKey: Self.rememberedEmailKey)
        }
    }

    private func restoredOrHydratedUser(in modelContext: ModelContext) -> User? {
        let users = fetchUsers(in: modelContext)
        if let restoredUser = restoredUser(from: users) {
            return restoredUser
        }

        let defaults = UserDefaults.standard
        if let persistedGoogleUserID = defaults.string(forKey: Self.persistedGoogleUserIDKey),
           let storedAccount = LocalAccountStore.account(googleUserID: persistedGoogleUserID) {
            return resolvedUser(forEmail: storedAccount.email, in: modelContext, cachedUsers: users)
        }

        if let persistedEmail = persistedSessionEmail() {
            return resolvedUser(forEmail: persistedEmail, in: modelContext, cachedUsers: users)
        }

        return nil
    }

    private func currentSessionEmail() -> String? {
        guard let currentUserEmail else {
            return nil
        }

        let normalizedEmail = normalizedEmail(currentUserEmail)

        return normalizedEmail.isEmpty ? nil : normalizedEmail
    }

    private func persistedSessionEmail() -> String? {
        let normalizedEmail = UserDefaults.standard.string(forKey: Self.persistedEmailKey)?
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let normalizedEmail, !normalizedEmail.isEmpty else {
            return nil
        }

        return normalizedEmail
    }

    func logout() {
        clearPersistedSession()
        currentUserEmail = nil
        chosenstudyAreas = []
        activestudyArea = ""
        streakCount = 0
        loginError = ""
        password = ""
        isLoggedIn = false
        isSignedUp = false
        showCreateSheet = false
        pendingNavigation = nil
        clearFlashcardDraft()
        navPath = NavigationPath()

        if !rememberMePreference {
            email = ""
        }
    }
}

private struct StoredAccount: Codable {
    let email: String
    let password: String?
    let googleUserID: String?
    let savedstudyAreas: [String]
    let streakCount: Int
    let lastActivityDate: Date?

    init(
        email: String,
        password: String?,
        googleUserID: String?,
        savedstudyAreas: [String],
        streakCount: Int,
        lastActivityDate: Date?
    ) {
        self.email = email
        self.password = password
        self.googleUserID = googleUserID
        self.savedstudyAreas = savedstudyAreas
        self.streakCount = streakCount
        self.lastActivityDate = lastActivityDate
    }

    init(user: User) {
        self.email = user.email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = user.password
        self.googleUserID = user.googleUserID
        self.savedstudyAreas = user.savedstudyAreas
        self.streakCount = user.streakCount
        self.lastActivityDate = user.lastActivityDate
    }
}

private enum LocalAccountStore {
    private nonisolated static let accountsKey = "auth.local.accounts"

    nonisolated static func account(email: String) -> StoredAccount? {
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return loadAccounts().first { $0.email == normalizedEmail }
    }

    nonisolated static func account(googleUserID: String) -> StoredAccount? {
        loadAccounts().first { $0.googleUserID == googleUserID }
    }

    nonisolated static func upsert(from user: User) {
        var accounts = loadAccounts()
        let storedAccount = StoredAccount(user: user)

        if let index = accounts.firstIndex(where: { $0.email == storedAccount.email }) {
            accounts[index] = storedAccount
        } else {
            accounts.append(storedAccount)
        }

        saveAccounts(accounts)
    }

    nonisolated static func updateStudyAreas(_ studyAreas: [String], forEmail email: String) {
        var accounts = loadAccounts()
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        guard let index = accounts.firstIndex(where: { $0.email == normalizedEmail }) else {
            return
        }

        let current = accounts[index]
        accounts[index] = StoredAccount(
            email: current.email,
            password: current.password,
            googleUserID: current.googleUserID,
            savedstudyAreas: studyAreas,
            streakCount: current.streakCount,
            lastActivityDate: current.lastActivityDate
        )
        saveAccounts(accounts)
    }

    private nonisolated static func loadAccounts() -> [StoredAccount] {
        guard let data = UserDefaults.standard.data(forKey: accountsKey) else {
            return []
        }

        return (try? JSONDecoder().decode([StoredAccount].self, from: data)) ?? []
    }

    private nonisolated static func saveAccounts(_ accounts: [StoredAccount]) {
        guard let data = try? JSONEncoder().encode(accounts) else {
            return
        }

        UserDefaults.standard.set(data, forKey: accountsKey)
    }
}
