import SwiftUI

struct StartView: View {
    @State private var isAnimating = false
    
    var body: some View {
        
        
        ZStack {
            // Background Color
            Color(red: 0.11, green: 0.49, blue: 0.95)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Owl icon
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 240, height: 240)
                    
                    Image("owl_mascot")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 200, height: 200)
                        .clipShape(Circle())
                        .scaleEffect(isAnimating ? 1.1 : 1.0)
                }
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                        isAnimating = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            isAnimating = false
                        }
                    }
                }
                
                Spacer()
                
                // The White Card Section
                VStack(spacing: 140) {
                    Text("Lets get learning!")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.11, green: 0.49, blue: 0.95))
                        .padding(.top, 50)
                    
                    
                    NavigationLink(value: NavTarget.signup) {
                        Text("Get Started")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color(red: 0.11, green: 0.49, blue: 0.95))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 90)
                }
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40))
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}


#Preview {
    StartView()
}
