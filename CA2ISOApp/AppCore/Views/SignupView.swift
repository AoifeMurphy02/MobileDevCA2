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
            AppTheme.primary.ignoresSafeArea()
            
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
                        .foregroundColor(AppTheme.primary)
                        .padding(.top, 30)

                    // Email Field
                    HStack {
                        Image(systemName: "envelope")
                            .foregroundColor(AppTheme.primary)
                        TextField("Email", text: $viewModel.email)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.emailAddress)
                            .foregroundColor(AppTheme.text)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.subtleBorder))
                    .padding(.horizontal, 30)
                    
                    // Password Field
                    AuthPasswordField(password: $viewModel.password)
                    .padding(.horizontal, 30)
                    
                    // T and C
                    Toggle(isOn: $viewModel.hasAgreedToTerms) {
                        Text("Agree to Terms & Conditions")
                            .font(.caption)
                            .foregroundColor(AppTheme.text)
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
                        .background(AppTheme.primary)
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 30)
                    
                    Text("Or Continue With")
                        .font(.caption)
                        .foregroundColor(AppTheme.text)
                    
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
                                .foregroundColor(AppTheme.text)
                            Text("SIGN IN")
                                .fontWeight(.bold)
                                .foregroundColor(AppTheme.primary)
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
        .toolbar(.hidden, for: .navigationBar)
        .disableSwipeBack()
        .onAppear {
            viewModel.loginError = ""
        }
    }
}

struct CheckboxStyle: ToggleStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        return HStack {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .foregroundColor(configuration.isOn ? .green : AppTheme.text)
                .onTapGesture { configuration.isOn.toggle() }
            configuration.label
        }
    }
}

struct SocialButton: View {
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
        SignupView()
            .environment(AppViewModel())
    }
}
