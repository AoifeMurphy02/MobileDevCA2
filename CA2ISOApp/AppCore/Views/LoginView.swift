//
//  LoginView.swift
//  CA2ISOApp
//
//  Created by Aoife on 24/03/2026.
//

import Foundation
import SwiftUI
import SwiftData

struct LoginView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var rememberMe = false
    
    @Query var allUsers: [User]

    
    var body: some View {
        @Bindable var viewModel = viewModel 
        ZStack {
            // Background Blue
            Color(red: 0.11, green: 0.49, blue: 0.95).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Owl Image
                Image("owl_mascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .padding(.top, 30)
                
                Spacer()
                
                // White Card Section
                VStack(spacing: 20) {
                    Text("Welcome Back!")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.11, green: 0.49, blue: 0.95))
                        .padding(.top, 30)
                    
                    // Email Field
                    HStack {
                        Image(systemName: "envelope")
                            .foregroundColor(.gray)
                        TextField("Email", text: $viewModel.email)
                            .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .keyboardType(.emailAddress)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3)))
                    .padding(.horizontal, 30)
                    
                    // Password Field
                    HStack {
                        Image(systemName: "lock")
                            .foregroundColor(.gray)
                        SecureField("Password", text: $viewModel.password)
                        Image(systemName: "eye.slash")
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3)))
                    .padding(.horizontal, 30)
                    
                    // Remember Me Toggle
                    HStack {
                        Toggle(isOn: $rememberMe) {
                            Text("Remember Me")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .toggleStyle(LoginCheckboxStyle())
                        Spacer()
                    }
                    .padding(.horizontal, 30)
                    
                    if !viewModel.loginError.isEmpty {
                        Text(viewModel.loginError)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                    
                    
                    Button(action: {
                     
                        viewModel.loginUser(users: allUsers)
                        
                    }) {
                        HStack {
                            Spacer()
                            Text("Sign In")
                            Spacer()
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title2)
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Color(red: 0.11, green: 0.49, blue: 0.95))
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 30)
                    
                    Text("Or Continue With")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    // Icons
                    HStack(spacing: 30) {
                        LoginSocialButton(imageName: "google")
                        LoginSocialButton(imageName: "apple")
                    }
                    
                    // Link to Sign Up
                    NavigationLink(value: NavTarget.signup)  {
                        HStack(spacing: 4) {
                            Text("Don't have an Account?")
                                .foregroundColor(.gray)
                            Text("SIGN UP")
                                .fontWeight(.bold)
                                .foregroundColor(Color(red: 0.11, green: 0.49, blue: 0.95))
                        }
                        .font(.caption)
                    }
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40))
            }
            .ignoresSafeArea(edges: .bottom)
        }
        // Hides the automatic back button to keep the design clean
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $viewModel.isLoggedIn) {
            HomeView()
        }
    }
    
    
    
    struct LoginCheckboxStyle: ToggleStyle {
        func makeBody(configuration: Self.Configuration) -> some View {
            return HStack {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundColor(configuration.isOn ? Color(red: 0.11, green: 0.49, blue: 0.95) : .gray)
                    .onTapGesture { configuration.isOn.toggle() }
                configuration.label
            }
        }
    }
    
    struct LoginSocialButton: View {
        var imageName: String
        
        var body: some View {
            Circle()
                .fill(Color.white)
                .frame(width: 45, height: 45)
                .shadow(color: .black.opacity(0.1), radius: 5)
                .overlay(
                    Group {
                        if imageName == "apple" {
                            // Apple official system icon
                            Image(systemName: "applelogo")
                                .font(.title3)
                                .foregroundColor(.black)
                        } else {
                            
                            Image(imageName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 25, height: 25)
                        }
                    }
                )
        }
    }
}

#Preview {
    NavigationStack {
        LoginView()
            .environment(AppViewModel())
    }
}
