//
//  LibrariesViewModel.swift
//  CA2ISOApp
//
//  Created by Meghana on 05/05/2026.
//

import Combine
import CoreLocation
import Foundation
import MapKit
import SwiftUI

struct StudyLibrary: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var distanceText: String {
        if distanceMeters >= 1000 {
            return String(format: "%.1f km away", distanceMeters / 1000)
        }

        return "\(Int(distanceMeters)) m away"
    }
}

enum LibraryTransportMode: String, CaseIterable, Identifiable {
    case walking = "Walk"
    case driving = "Drive"
    case transit = "Transit"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .walking: return "figure.walk"
        case .driving: return "car.fill"
        case .transit: return "bus.fill"
        }
    }

    var mapKitType: MKDirectionsTransportType {
        switch self {
        case .walking: return .walking
        case .driving: return .automobile
        case .transit: return .transit
        }
    }

    var mapsLaunchOption: String {
        switch self {
        case .walking: return MKLaunchOptionsDirectionsModeWalking
        case .driving: return MKLaunchOptionsDirectionsModeDriving
        case .transit: return MKLaunchOptionsDirectionsModeTransit
        }
    }
}

@MainActor
final class LibrariesViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var libraries: [StudyLibrary] = []
    @Published var savedLibraries: [StudyLibrary] = []
    @Published var selectedLibrary: StudyLibrary?
    @Published var selectedTransport: LibraryTransportMode = .walking
    @Published var route: MKRoute?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var message = "Allow location access to find study-friendly libraries near you."
    @Published var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 53.3498, longitude: -6.2603),
            latitudinalMeters: 9000,
            longitudinalMeters: 9000
        )
    )

    private static let savedLibrariesKey = "libraries.saved.items"

    private let locationManager = CLLocationManager()
    private var userCoordinate: CLLocationCoordinate2D?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        loadSavedLibraries()
    }

    func requestLibrariesNearMe() {
        errorMessage = nil

        switch locationManager.authorizationStatus {
        case .notDetermined:
            message = "SmartDeck uses your location only to find nearby libraries."
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isLoading = true
            message = "Finding nearby libraries..."
            locationManager.requestLocation()
        case .denied, .restricted:
            finishWithError("Location permission is off. Enable it in Settings to find nearby libraries.")
        @unknown default:
            finishWithError("Unable to check location permission right now.")
        }
    }

    func toggleSaved(_ library: StudyLibrary) {
        if let index = savedLibraries.firstIndex(where: { $0.id == library.id }) {
            savedLibraries.remove(at: index)
            message = "Removed \(library.name) from saved libraries."
        } else {
            savedLibraries.insert(library, at: 0)
            message = "Saved \(library.name). Open it later to get the route."
        }

        saveLibraries()
    }

    func isSaved(_ library: StudyLibrary) -> Bool {
        savedLibraries.contains(where: { $0.id == library.id })
    }

    func showRoute(to library: StudyLibrary) {
        selectedLibrary = library
        route = nil

        guard let userCoordinate else {
            finishWithError("Location is needed before SmartDeck can draw a route.")
            requestLibrariesNearMe()
            return
        }

        Task {
            await calculateRoute(from: userCoordinate, to: library)
        }
    }

    func selectTransport(_ transport: LibraryTransportMode) {
        selectedTransport = transport

        guard let selectedLibrary else { return }
        showRoute(to: selectedLibrary)
    }

    func openSelectedRouteInMaps() {
        guard let selectedLibrary else {
            finishWithError("Choose a library first, then SmartDeck can open directions.")
            return
        }

        let placemark = MKPlacemark(coordinate: selectedLibrary.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = selectedLibrary.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: selectedTransport.mapsLaunchOption
        ])
    }

    var routeSummary: String? {
        guard let route else { return nil }

        let minutes = max(Int(route.expectedTravelTime / 60), 1)
        let distance: String

        if route.distance >= 1000 {
            distance = String(format: "%.1f km", route.distance / 1000)
        } else {
            distance = "\(Int(route.distance)) m"
        }

        return "\(selectedTransport.rawValue) route • \(minutes) min • \(distance)"
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            requestLibrariesNearMe()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finishWithError("Could not read your current location.")
            return
        }

        userCoordinate = location.coordinate
        cameraPosition = .region(
            MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 8000,
                longitudinalMeters: 8000
            )
        )

        Task {
            await searchLibraries(near: location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finishWithError("Location failed: \(error.localizedDescription)")
    }

    private func searchLibraries(near location: CLLocation) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "library"
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 9000,
            longitudinalMeters: 9000
        )

        do {
            let response = try await MKLocalSearch(request: request).start()
            libraries = response.mapItems
                .compactMap { makeLibrary(from: $0, userLocation: location) }
                .sorted { $0.distanceMeters < $1.distanceMeters }
            finishWithMessage(libraries.isEmpty ? "No nearby libraries found." : "Double-tap a library card to save it.")
        } catch {
            finishWithError("Library search failed: \(error.localizedDescription)")
        }
    }

    private func calculateRoute(from start: CLLocationCoordinate2D, to library: StudyLibrary) async {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: library.coordinate))
        request.transportType = selectedTransport.mapKitType

        do {
            let response = try await MKDirections(request: request).calculate()
            route = response.routes.first
            message = route == nil ? "No \(selectedTransport.rawValue.lowercased()) route found." : "Route ready for \(library.name)."
        } catch {
            finishWithError("Route failed: \(error.localizedDescription)")
        }
    }

    private func makeLibrary(from item: MKMapItem, userLocation: CLLocation) -> StudyLibrary? {
        guard let name = item.name else { return nil }

        let coordinate = item.placemark.coordinate
        let libraryLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let address = [
            item.placemark.thoroughfare,
            item.placemark.locality,
            item.placemark.postalCode
        ]
        .compactMap { $0 }
        .joined(separator: ", ")

        return StudyLibrary(
            id: "\(name)-\(coordinate.latitude)-\(coordinate.longitude)",
            name: name,
            address: address.isEmpty ? "Address unavailable" : address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            distanceMeters: userLocation.distance(from: libraryLocation)
        )
    }

    private func loadSavedLibraries() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedLibrariesKey) else { return }
        savedLibraries = (try? JSONDecoder().decode([StudyLibrary].self, from: data)) ?? []
    }

    private func saveLibraries() {
        guard let data = try? JSONEncoder().encode(savedLibraries) else { return }
        UserDefaults.standard.set(data, forKey: Self.savedLibrariesKey)
    }

    private func finishWithMessage(_ text: String) {
        isLoading = false
        errorMessage = nil
        message = text
    }

    private func finishWithError(_ text: String) {
        isLoading = false
        errorMessage = text
        message = text
    }
}
