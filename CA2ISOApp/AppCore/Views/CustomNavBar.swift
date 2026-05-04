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
    // This tells the bar which tab is currently selected
    // 0 = Home, 1 = Add, 2 = Clock
    var selectedTab: Int
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.1)

            HStack {
                Spacer()

                Button(action: {
                    viewModel.showCreateSheet = false

                    guard selectedTab != 0 else { return }
                    viewModel.navPath = NavigationPath()
                    viewModel.navPath.append(NavTarget.home)
                }) {
                    NavBarIcon(iconName: "house", isSelected: selectedTab == 0)
                }

                Spacer()

                // add
                Button(action: {
                    viewModel.showCreateSheet = true
                }) {
                    ZStack {
                        if selectedTab == 1 {
                            Circle()
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: 50, height: 50)
                        }

                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundColor(AppTheme.text)
                    }
                }

                Spacer()

                // clock
                Button(action: {
                    viewModel.showCreateSheet = false

                    guard selectedTab != 2 else { return }
                    viewModel.navPath.append(NavTarget.timer)
                }) {
                    NavBarIcon(iconName: "clock", isSelected: selectedTab == 2)
                }

                Spacer()
            }
            .frame(height: 60)
            .background(
                AppTheme.navBackground
                    .ignoresSafeArea(edges: .bottom)
            )
        }
    }
}

struct NavBarIcon: View {
    var iconName: String
    var isSelected: Bool
    
    var body: some View {
        ZStack {
            if isSelected {
                Capsule()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 60, height: 35)
            }
            
            Image(systemName: iconName)
                .font(.title3)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundColor(AppTheme.text)
        }
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
