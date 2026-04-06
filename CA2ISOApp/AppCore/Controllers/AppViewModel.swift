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
            print("MATCH FOUND: Found user with email \(foundUser.email)")
            
            if foundUser.password == password {
                print("PASSWORD CORRECT: Triggering navigation...")
                self.isLoggedIn = true
            } else {
                print("ERROR: Password typed [\(password)] does not match saved [\(foundUser.password)]")
                self.loginError = "Wrong password."
            }
        } else {
            print("ERROR: No user found with email [\(cleanEmail)]")
            self.loginError = "User not found."
        }
    }
}
