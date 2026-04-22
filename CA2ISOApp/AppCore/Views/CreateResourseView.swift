import Foundation
import SwiftUI

struct CreateResourceView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        //GeometryReader { geometry in
          //  ZStack(alignment: .bottom) {
            //    Color.black.opacity(0.08)
              //      .ignoresSafeArea()

                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 58, height: 6)
                        .padding(.top, 14)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Quick Create")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(red: 0.11, green: 0.49, blue: 0.95))

                                Text("Jump into the parts of the app that are ready to use right now.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button {
                                viewModel.showCreateSheet = false
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                    .frame(width: 34, height: 34)
                                    .background(Color.gray.opacity(0.1))
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 22)
                    .padding(.bottom, 18)

                    VStack(spacing: 16) {
                        ResourceActionButton(
                            title: "AI Flashcards",
                            subtitle: "Import notes, PDFs, or images and build a smart deck.",
                            icon: "sparkles.rectangle.stack.fill",
                            iconColor: .cyan
                        ) {
                            viewModel.pendingNavigation = .flashcards
                            viewModel.showCreateSheet = false
                        }

                        ResourceActionButton(
                            title: "Manual Deck",
                            subtitle: "Start with a question and answer, then edit the deck.",
                            icon: "square.and.pencil",
                            iconColor: .green
                        ) {
                            viewModel.pendingNavigation = .createFlashcardsManually
                            viewModel.showCreateSheet = false
                        }

                        ResourceActionButton(
                            title: "Study Timer",
                            subtitle: "Open a focus timer and keep your study streak going.",
                            icon: "timer",
                            iconColor: .orange
                        ) {
                            viewModel.pendingNavigation = .timer
                            viewModel.showCreateSheet = false
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 8)

                    Spacer()
                }
              // .frame(maxWidth: .infinity, maxHeight: min(geometry.size.height * 0.62, 470))
                .background(Color.white)
               // .clipShape(UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40))
            }
        }
     //   .ignoresSafeArea(edges: .bottom)
  //  }
//}

struct ResourceActionButton: View {
    var title: String
    var subtitle: String
    var icon: String
    var iconColor: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(iconColor)
                    .frame(width: 56, height: 56)
                    .background(iconColor.opacity(0.1))
                    .cornerRadius(14)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.black)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18).stroke(Color.blue.opacity(0.18), lineWidth: 1.4))
            .background(Color.white)
            .cornerRadius(18)
        }
    }
}

#Preview {
    NavigationStack {
        CreateResourceView()
            .environment(AppViewModel())
    }
}
