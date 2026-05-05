//
//  LibrariesView.swift
//  CA2ISOApp
//
//  Created by Meghana on 05/05/2026.
//

import MapKit
import SwiftUI

struct LibrariesView: View {
    @StateObject private var libraryVM = LibrariesViewModel()
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    mapCard
                    savedSection
                    nearbySection
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 110)
            }
            .background(AppTheme.background)

            CustomNavBar(selectedTab: 3)
        }
        .navigationBarBackButtonHidden(true)
        .enableSwipeBack()
        .onAppear {
            if libraryVM.libraries.isEmpty {
                libraryVM.requestLibrariesNearMe()
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showCreateSheet },
            set: { viewModel.showCreateSheet = $0 }
        )) {
            CreateResourceView()
                .presentationDetents([.medium])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Study Libraries")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.text)

            Text("Find nearby libraries, double-tap to save one, then choose how you want to get there.")
                .font(.subheadline)
                .foregroundColor(AppTheme.secondaryText)
        }
    }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Map(position: $libraryVM.cameraPosition) {
                UserAnnotation()

                ForEach(libraryVM.libraries) { library in
                    Marker(library.name, systemImage: libraryVM.isSaved(library) ? "heart.fill" : "books.vertical.fill", coordinate: library.coordinate)
                        .tint(libraryVM.isSaved(library) ? .pink : AppTheme.primary)
                }

                if let route = libraryVM.route {
                    MapPolyline(route.polyline)
                        .stroke(AppTheme.primary, lineWidth: 6)
                }
            }
            .frame(height: 310)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppTheme.subtleBorder, lineWidth: 1)
            )

            HStack(spacing: 10) {
                if libraryVM.isLoading {
                    ProgressView()
                } else {
                    Image(systemName: libraryVM.errorMessage == nil ? "location.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(libraryVM.errorMessage == nil ? AppTheme.primary : .orange)
                }

                Text(libraryVM.message)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(libraryVM.errorMessage == nil ? AppTheme.secondaryText : .orange)
                    .lineLimit(2)

                Spacer()

                Button("Refresh") {
                    libraryVM.requestLibrariesNearMe()
                }
                .font(.caption.weight(.bold))
                .foregroundColor(AppTheme.primary)
            }

            routeControls
        }
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
    }

    private var routeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(LibraryTransportMode.allCases) { transport in
                    Button {
                        libraryVM.selectTransport(transport)
                    } label: {
                        Label(transport.rawValue, systemImage: transport.iconName)
                            .font(.caption.weight(.bold))
                            .foregroundColor(libraryVM.selectedTransport == transport ? .white : AppTheme.primary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(libraryVM.selectedTransport == transport ? AppTheme.primary : AppTheme.primary.opacity(0.10))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if let selectedLibrary = libraryVM.selectedLibrary {
                HStack(spacing: 10) {
                    Image(systemName: "map.fill")
                        .foregroundColor(AppTheme.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(libraryVM.routeSummary ?? "Route selected")
                            .font(.caption.weight(.bold))
                            .foregroundColor(AppTheme.text)

                        Text(selectedLibrary.name)
                            .font(.caption2)
                            .foregroundColor(AppTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button("Open in Maps") {
                        libraryVM.openSelectedRouteInMaps()
                    }
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.primary)
                    .clipShape(Capsule())
                }
                .padding(12)
                .background(AppTheme.secondarySurface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                Text("Tap the route arrow on any library card to draw a route here.")
                    .font(.caption)
                    .foregroundColor(AppTheme.secondaryText)
            }
        }
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved for Later")
                .font(.title3.bold())
                .foregroundColor(AppTheme.text)

            if libraryVM.savedLibraries.isEmpty {
                EmptyLibraryCard(
                    icon: "heart",
                    title: "No saved libraries yet",
                    message: "Double-tap a nearby library card to save it here."
                )
            } else {
                ForEach(libraryVM.savedLibraries) { library in
                    LibraryCard(
                        library: library,
                        isSaved: true,
                        saveHint: "Double-tap to remove",
                        onDoubleTap: { libraryVM.toggleSaved(library) },
                        onRoute: { libraryVM.showRoute(to: library) }
                    )
                }
            }
        }
    }

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nearby Libraries")
                .font(.title3.bold())
                .foregroundColor(AppTheme.text)

            if libraryVM.libraries.isEmpty && !libraryVM.isLoading {
                EmptyLibraryCard(
                    icon: "building.columns",
                    title: "Search nearby",
                    message: "Allow location access and SmartDeck will show libraries close to you."
                )
            } else {
                ForEach(libraryVM.libraries) { library in
                    LibraryCard(
                        library: library,
                        isSaved: libraryVM.isSaved(library),
                        saveHint: libraryVM.isSaved(library) ? "Double-tap to unsave" : "Double-tap to save",
                        onDoubleTap: { libraryVM.toggleSaved(library) },
                        onRoute: { libraryVM.showRoute(to: library) }
                    )
                }
            }
        }
    }
}

private struct LibraryCard: View {
    let library: StudyLibrary
    let isSaved: Bool
    let saveHint: String
    let onDoubleTap: () -> Void
    let onRoute: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isSaved ? "heart.fill" : "books.vertical.fill")
                .font(.title3)
                .foregroundColor(isSaved ? .pink : AppTheme.primary)
                .frame(width: 46, height: 46)
                .background((isSaved ? Color.pink : AppTheme.primary).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(library.name)
                    .font(.headline)
                    .foregroundColor(AppTheme.text)
                    .lineLimit(2)

                Text(library.address)
                    .font(.caption)
                    .foregroundColor(AppTheme.secondaryText)
                    .lineLimit(1)

                Text("\(library.distanceText) • \(saveHint)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppTheme.primary)
            }

            Spacer()

            Button(action: onRoute) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.primary)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Show route to \(library.name)")
        }
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isSaved ? Color.pink.opacity(0.22) : AppTheme.subtleBorder, lineWidth: 1)
        )
        .onTapGesture(count: 2, perform: onDoubleTap)
    }
}

private struct EmptyLibraryCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(AppTheme.primary)
                .frame(width: 48, height: 48)
                .background(AppTheme.primary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppTheme.text)

                Text(message)
                    .font(.caption)
                    .foregroundColor(AppTheme.secondaryText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        LibrariesView()
            .environment(AppViewModel())
    }
}
