//
//  LoginView.swift
//  CA2ISOApp
//
//  Created by Aoife on 24/03/2026.
//

import SwiftUI
import SwiftData
import GoogleSignIn

struct LoginView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @State private var rememberMe = false

    var body: some View {
       @Bindable var viewModel = viewModel
        ZStack {
            // Background Blue
            AppTheme.primary.ignoresSafeArea()
            
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
                        .foregroundColor(AppTheme.primary)
                        .padding(.top, 30)

                    Text("Sign in to open your study spaces, saved decks, and streak.")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.text)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                    
                    // Input Fields
                    Group {
                        HStack {
                            Image(systemName: "envelope").foregroundColor(AppTheme.primary)
                            TextField("Email", text: $viewModel.email)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .keyboardType(.emailAddress)
                                .foregroundColor(AppTheme.text)
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.subtleBorder))
                        
                        HStack {
                            Image(systemName: "lock").foregroundColor(AppTheme.primary)
                            SecureField("Password", text: $viewModel.password)
                                .foregroundColor(AppTheme.text)
                            Image(systemName: "eye.slash").foregroundColor(AppTheme.primary)
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.subtleBorder))
                    }
                    .padding(.horizontal, 30)
                    
                    // Remember Me Toggle
                    HStack {
                        Toggle(isOn: $rememberMe) {
                            Text("Remember Me").font(.caption).foregroundColor(AppTheme.text)
                        }
                        .toggleStyle(LoginCheckboxStyle())
                        Spacer()
                    }
                    .padding(.horizontal, 30)
                    
                    // Error Handling
                    if !viewModel.loginError.isEmpty {
                        Text(viewModel.loginError).font(.caption).foregroundColor(.red).padding(.horizontal)
                    }
                    
                    // Main Sign In Button
                    Button(action: {
                        viewModel.loginUser(modelContext: modelContext, rememberCredentials: rememberMe)
                    }) {
                        HStack {
                            Spacer(); Text("Sign In"); Spacer()
                            Image(systemName: "arrow.right.circle.fill").font(.title2)
                        }
                        .foregroundColor(.white).padding().background(AppTheme.primary).clipShape(Capsule())
                    }
                    .padding(.horizontal, 30)
                    
                    Text("Or Continue With").font(.caption).foregroundColor(AppTheme.text)
                    
                    // --- SOCIAL ICONS SECTION (FIXED) ---
                    HStack(spacing: 30) {
                        
                        // 1. GOOGLE BUTTON
                        ZStack {
                            LoginSocialButton(imageName: "google")
                            
                            // This transparent button handles the tap
                            Button(action: {
                                // Try real Google Login first
                                // If SDK isn't set up, you can change this to .mockGoogleSignIn
                                viewModel.handleGoogleSignIn(modelContext: modelContext)
                            }) {
                                Circle().fill(AppTheme.surface.opacity(0.01))
                            }
                            .frame(width: 45, height: 45)
                            
                        }
                    }
                    
                    // Link to Sign Up
                    NavigationLink(value: NavTarget.signup)  {
                        HStack(spacing: 4) {
                            Text("Don't have an Account?").foregroundColor(AppTheme.text)
                            Text("SIGN UP").fontWeight(.bold).foregroundColor(AppTheme.primary)
                        }
                        .font(.caption)
                    }
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity)
                .background(AppTheme.surface)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40))
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationBarBackButtonHidden(true)
        .disableSwipeBack()
        .onAppear {
            viewModel.loginError = ""
            viewModel.loadRememberedCredentials()
            rememberMe = viewModel.rememberMePreference
        }
    }
}

// MARK: - Helper Styles
struct LoginCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        return HStack {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .foregroundColor(configuration.isOn ? AppTheme.primary : AppTheme.text)
                .onTapGesture { configuration.isOn.toggle() }
            configuration.label
        }
    }
}

struct LoginSocialButton: View {
    var imageName: String
    var body: some View {
        Circle()
            .fill(AppTheme.secondarySurface)
            .frame(width: 45, height: 45)
            .overlay(Circle().stroke(AppTheme.subtleBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.16), radius: 5)
            .overlay(
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 25, height: 25)
            )
    }
}

#Preview {
    NavigationStack {
        LoginView().environment(AppViewModel())
    }
}
