import Foundation
import SwiftUI
import SwiftData

struct SignupView: View {
    @Environment(AppViewModel.self) private var viewModel
    
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
       @Bindable var viewModel = viewModel
        
        ZStack {
            // Background Blue
            Color(red: 0.11, green: 0.49, blue: 0.95).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Owl image
                Image("owl_mascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .padding(.top, 30)
                
                Spacer()
                
                // White Card
                VStack(spacing: 20) {
                    Text("Getting Started!")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.11, green: 0.49, blue: 0.95))
                        .padding(.top, 30)

                    Text("Create your account to organize studyAreas, build flashcard decks, and keep your study streak going.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 34)
                    
                    // Email Field
                    HStack {
                        Image(systemName: "envelope")
                            .foregroundColor(.gray)
                        TextField("Email", text: $viewModel.email)
                            .textInputAutocapitalization(.never)
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
                    
                    // T and C
                    Toggle(isOn: $viewModel.hasAgreedToTerms) {
                        Text("Agree to Terms & Conditions")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .toggleStyle(CheckboxStyle())
                    .padding(.horizontal, 30)

                    if !viewModel.loginError.isEmpty {
                        Text(viewModel.loginError)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal, 30)
                    }
                    
                    // The sign up Button
                    
                    Button(action: {
                        
                        viewModel.signUpUser(modelContext: modelContext)
                    }) {
                        HStack {
                            Spacer()
                            Text("Sign Up")
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
                    
                    // Social Icons
                    
                    HStack(spacing: 30) {
                        // GOOGLE BUTTON
                        ZStack {
                            Button(action: {
                                print("DEBUG: Google Sign-In Tapped")
                                viewModel.handleGoogleSignIn(modelContext: modelContext)
                            }) {
                                SocialButton(imageName: "google")
                            }
                        }
                    }
                    .padding(.top, 10)

                    NavigationLink(value: NavTarget.login) {
                        HStack(spacing: 4) {
                            Text("Already have an Account?")
                                .foregroundColor(.gray)
                            Text("SIGN IN")
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
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .enableSwipeBack()
        .navigationDestination(isPresented: $viewModel.isSignedUp) {
            studyAreaPickerView()
        }
        .onAppear {
            viewModel.loginError = ""
        }
    }
}

struct CheckboxStyle: ToggleStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        return HStack {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .foregroundColor(configuration.isOn ? .green : .gray)
                .onTapGesture { configuration.isOn.toggle() }
            configuration.label
        }
    }
}

struct SocialButton: View {
    var imageName: String
    
    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 45, height: 45)
            .shadow(color: .black.opacity(0.1), radius: 5)
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
        SignupView()
            .environment(AppViewModel())
    }
}
