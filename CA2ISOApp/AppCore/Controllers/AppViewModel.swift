//
//  AppViewModel.swift
//  CA2ISOApp
//
//  Created by Aoife on 24/03/2026.
//
import Foundation
import Observation
import SwiftData

@Observable
class AppViewModel {
    
    var email = ""
    var password = ""
    var hasAgreedToTerms = false
    
    var isLoggedIn = false // New state to trigger navigation to Home
    var loginError = ""    // For error handling

    
    // was sign up successful if so we move screens
    var isSignedUp = false

    //  save the user
    func signUpUser(modelContext: ModelContext) {
        guard !email.isEmpty, !password.isEmpty, hasAgreedToTerms else {
            print("Error: Missing information")
            return
        }
        
        // Clean the email before saving (Best Practice)
        let cleanEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let newUser = User(email: cleanEmail, password: password)
        
        // 1. Insert into memory
        modelContext.insert(newUser)
        
        // 2. FORCE save to the phone's disk
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
        print("--- LOGIN TEST START ---")
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
