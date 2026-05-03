//
//  User.swift
//  CA2ISOApp
//
//  Created by Aoife on 24/03/2026.
//

import Foundation
import SwiftData

@Model
class User {
    var email: String
    var appleUserID: String?
    var googleUserID: String?
    var password: String?
    //var password: String
    var signUpDate: Date
    var savedstudySubjects: [String] = []
    var streakCount: Int = 0
    var lastActivityDate: Date?
    
    init(email: String, password: String? = nil, appleUserID: String? = nil, googleUserID: String? = nil, savedstudySubjects: [String] = [])  {
        self.email = email
        self.password = password
        self.appleUserID = appleUserID
        self.googleUserID = googleUserID
        self.savedstudySubjects = savedstudySubjects
        self.signUpDate = Date.now
    }
}
