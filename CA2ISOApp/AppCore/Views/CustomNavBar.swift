//
//  CustomNavBar.swift
//  CA2ISOApp
//
//  Created by Aoife on 01/04/2026.
//

import Foundation
import SwiftUI
import UIKit

enum AppTheme {
    static let primary = Color(red: 0.11, green: 0.49, blue: 0.95)
    static let primarySoft = Color(red: 0.25, green: 0.53, blue: 0.94)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .systemBackground)
    static let secondarySurface = Color(uiColor: .secondarySystemGroupedBackground)
    static let text = Color(uiColor: .label)
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let subtleBorder = Color(uiColor: .separator).opacity(0.35)
    static let navBackground = Color(uiColor: .secondarySystemGroupedBackground)
}

struct CustomNavBar: View {
    // 0 = Home, 1 = Create, 2 = Timer
    var selectedTab: Int
    @Environment(AppViewModel.self) private var viewModel
    @State private var showProfileSheet = false

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.16)

            HStack {
                NavBarButton(
                    iconName: selectedTab == 0 ? "house.fill" : "house",
                    title: "Home",
                    isSelected: selectedTab == 0
                ) {
                    viewModel.showCreateSheet = false

                    guard selectedTab != 0 else { return }
                    viewModel.navPath = NavigationPath()
                    viewModel.navPath.append(NavTarget.home)
                }

                NavBarButton(
                    iconName: "plus.circle.fill",
                    title: "Create",
                    isSelected: selectedTab == 1
                ) {
                    viewModel.showCreateSheet = true
                }

                NavBarButton(
                    iconName: selectedTab == 2 ? "timer.circle.fill" : "timer",
                    title: "Timer",
                    isSelected: selectedTab == 2
                ) {
                    viewModel.showCreateSheet = false

                    guard selectedTab != 2 else { return }
                    viewModel.navPath.append(NavTarget.timer)
                }

                NavBarButton(
                    iconName: "person.crop.circle",
                    title: "Profile",
                    isSelected: false
                ) {
                    viewModel.showCreateSheet = false
                    showProfileSheet = true
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(
                AppTheme.navBackground
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .sheet(isPresented: $showProfileSheet) {
            GlobalProfileSheetView(
                email: viewModel.activeSessionEmailForUI ?? "",
                streakCount: viewModel.streakCount,
                studyAreaCount: viewModel.studyAreaOptions.count,
                logoutAction: {
                    showProfileSheet = false
                    viewModel.logout()
                }
            )
            .presentationDetents([.height(560), .large])
        }
    }
}

private struct NavBarButton: View {
    var iconName: String
    var title: String
    var isSelected: Bool
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.system(size: 21, weight: isSelected ? .bold : .semibold))

                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundColor(isSelected ? AppTheme.primary : AppTheme.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? AppTheme.primary.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct GlobalProfileSheetView: View {
    let email: String
    let streakCount: Int
    let studyAreaCount: Int
    let logoutAction: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Capsule()
                    .fill(AppTheme.subtleBorder)
                    .frame(width: 42, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 2)

                HStack(spacing: 14) {
                    ProfileAvatar(initials: initials)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(displayName)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.text)

                        Text(email.isEmpty ? "No account email available" : email)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(AppTheme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.bottom, 2)

                HStack(spacing: 12) {
                    ProfileStatCard(
                        title: "Streak",
                        value: "\(streakCount)",
                        caption: streakCount == 1 ? "day" : "days",
                        icon: "flame.fill",
                        tint: Color.orange
                    )

                    ProfileStatCard(
                        title: "Spaces",
                        value: "\(studyAreaCount)",
                        caption: "active",
                        icon: "square.grid.2x2.fill",
                        tint: AppTheme.primary
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Account")
                        .font(.headline)
                        .foregroundColor(AppTheme.text)

                    ProfileInfoLine(title: "Signed in as", value: email.isEmpty ? "Unknown account" : email)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.secondarySurface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Button(role: .destructive, action: logoutAction) {
                    Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.headline)
                        .foregroundColor(Color.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(22)
        }
        .background(AppTheme.surface)
    }

    private var displayName: String {
        let username = email.components(separatedBy: "@").first ?? ""
        return username.isEmpty ? "SmartDeck User" : username.capitalized
    }

    private var initials: String {
        let letters = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        let initials = String(letters)
        return initials.isEmpty ? "S" : initials.uppercased()
    }
}

private struct ProfileAvatar: View {
    let initials: String

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [AppTheme.primary, AppTheme.primarySoft],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 64, height: 64)

            Text(initials)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }
}

private struct ProfileInfoLine: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppTheme.secondaryText)

            Text(value)
                .font(.headline)
                .foregroundColor(AppTheme.text)
        }
    }
}

private struct ProfileStatCard: View {
    let title: String
    let value: String
    let caption: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundColor(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12))
                .clipShape(Circle())

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppTheme.secondaryText)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.text)

                Text(caption)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.secondaryText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.secondarySurface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct SwipeBackEnabler: UIViewControllerRepresentable {
    let isEnabled: Bool

    func makeUIViewController(context: Context) -> SwipeBackHostingController {
        SwipeBackHostingController()
    }

    func updateUIViewController(_ uiViewController: SwipeBackHostingController, context: Context) {
        uiViewController.setSwipeBackEnabled(isEnabled)
    }
}

private final class SwipeBackHostingController: UIViewController {
    private var isSwipeBackEnabled = true

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applySwipeBackState()
    }

    func setSwipeBackEnabled(_ isEnabled: Bool) {
        isSwipeBackEnabled = isEnabled
        applySwipeBackState()
    }

    private func applySwipeBackState() {
        guard let navigationController else { return }

        if isSwipeBackEnabled {
            navigationController.interactivePopGestureRecognizer?.delegate = nil
        }

        navigationController.interactivePopGestureRecognizer?.isEnabled = isSwipeBackEnabled
    }
}

extension View {
    func enableSwipeBack() -> some View {
        background(SwipeBackEnabler(isEnabled: true).frame(width: 0, height: 0))
    }

    func disableSwipeBack() -> some View {
        background(SwipeBackEnabler(isEnabled: false).frame(width: 0, height: 0))
    }
}
