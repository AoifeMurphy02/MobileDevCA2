//
//  AppError.swift
//  CA2ISOApp
//
//  Created by Meghana on 05/05/2026.
//

import SwiftUI

enum AppErrorCategory: String {
    case validation = "Check Details"
    case permission = "Permission Needed"
    case storage = "Save Failed"
    case network = "Connection Problem"
    case importFailed = "Import Failed"
    case location = "Location Problem"
    case ai = "AI Error"
    case unknown = "Something Went Wrong"
}

struct AppError: Identifiable, Equatable {
    let id = UUID()
    let category: AppErrorCategory
    let message: String

    var title: String {
        category.rawValue
    }

    static func validation(_ message: String) -> AppError {
        AppError(category: .validation, message: message)
    }

    static func permission(_ message: String) -> AppError {
        AppError(category: .permission, message: message)
    }

    static func storage(_ message: String) -> AppError {
        AppError(category: .storage, message: message)
    }

    static func network(_ message: String) -> AppError {
        AppError(category: .network, message: message)
    }

    static func importFailed(_ message: String) -> AppError {
        AppError(category: .importFailed, message: message)
    }

    static func location(_ message: String) -> AppError {
        AppError(category: .location, message: message)
    }

    static func ai(_ message: String) -> AppError {
        AppError(category: .ai, message: message)
    }

    static func unknown(_ message: String) -> AppError {
        AppError(category: .unknown, message: message)
    }

    static func from(_ error: Error, fallbackMessage: String) -> AppError {
        let detail = error.localizedDescription
        let message = detail.isEmpty ? fallbackMessage : "\(fallbackMessage) \(detail)"
        return AppError(category: .unknown, message: message)
    }
}

extension View {
    func appErrorAlert(_ error: Binding<AppError?>) -> some View {
        alert(item: error) { appError in
            Alert(
                title: Text(appError.title),
                message: Text(appError.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
