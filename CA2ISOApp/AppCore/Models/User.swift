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
    var password: String
    var signUpDate: Date
    
    init(email: String, password: String) {
        self.email = email
        self.password = password
        self.signUpDate = Date.now
    }
}
