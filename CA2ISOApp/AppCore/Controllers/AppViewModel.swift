//
//  AppViewModel.swift
//  CA2ISOApp
//
//  Created by Aoife on 24/03/2026.
//
import Foundation
import Observation
import SwiftData

// Define the possible screens for navigation
enum NavTarget: Hashable {
    case flashcards
    case studyGuide
    case practiceTests
}

@Observable
class AppViewModel {
    
    var email = ""
    var password = ""
    var hasAgreedToTerms = false
    
    var isLoggedIn = false // New state to trigger navigation to Home
    var loginError = ""    // For error handling
    
    var chosenSubjects: [String] = []
    var currentUserEmail: String?
    //hardcoded for now
    var streakCount: Int = 2
    
    
    // was sign up successful if so we move screens
    var isSignedUp = false
    
    // Logic to control the pop-up sheet
    var showCreateSheet = false
    
    
    var activeNavigation: NavTarget? = nil
    
    //  save the user
    func signUpUser(modelContext: ModelContext) {
        guard !email.isEmpty, !password.isEmpty, hasAgreedToTerms else {
            print("Error: Missing information")
            return
        }
        
        // Clean the email before saving
        let cleanEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let newUser = User(email: cleanEmail, password: password)
        
        // Insert into memory
        modelContext.insert(newUser)
        
        // FORCE save to the phone's disk
        do {
            
            try modelContext.save()
            self.currentUserEmail = cleanEmail // Set the session immediately
            self.chosenSubjects = []
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
        
        let cleanEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        print("Searching for cleaned email: [\(cleanEmail)]")
        
        if let foundUser = users.first(where: { $0.email.lowercased() == cleanEmail }) {
            if foundUser.password == password {
                self.currentUserEmail = foundUser.email // Remember the user
                self.chosenSubjects = foundUser.savedSubjects // LOAD THEIR SUBJECTS
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
    
    //Save the subjects to the Database
    func persistSubjectsToDatabase(modelContext: ModelContext, users: [User]) {
        // Clean the session email to match the database format
        guard let sessionEmail = currentUserEmail?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else {
            print("DEBUG: No user email found in session. Cannot save.")
            return
        }
        
        // Find the user in the database (using case-insensitive check)
        if let userInDB = users.first(where: { $0.email.lowercased() == sessionEmail }) {
            
            // Sync the data
            userInDB.savedSubjects = self.chosenSubjects
            
            do {
                // Force SwiftData to write the change to the disk
                try modelContext.save()
                print("SUCCESS: Saved \(self.chosenSubjects.count) subjects for user: \(sessionEmail)")
            } catch {
                print("ERROR: Could not save to database: \(error.localizedDescription)")
            }
        } else {
            print("DEBUG: Could not find user [\(sessionEmail)] in database. Total users: \(users.count)")
        }
    }
}
