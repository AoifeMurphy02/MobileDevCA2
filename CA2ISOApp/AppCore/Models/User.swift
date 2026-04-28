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
    var savedSubjects: [String] = []
    
    init(email: String, password: String? = nil, appleUserID: String? = nil, googleUserID: String? = nil, savedSubjects: [String] = [])  {
        self.email = email
        self.password = password
        self.appleUserID = appleUserID
        self.googleUserID = googleUserID
        self.savedSubjects = savedSubjects
        self.signUpDate = Date.now
    }
}
