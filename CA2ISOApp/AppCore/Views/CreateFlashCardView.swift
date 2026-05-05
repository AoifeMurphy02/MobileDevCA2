//
//  CreateFlashCardView.swift
//  CA2ISOApp
//
//  Created by Aoife on 06/04/2026.
//

import Foundation
import AVFoundation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CreateFlashCardView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var allUsers: [User]
    @Query(sort: \FlashcardSet.createdAt, order: .reverse) private var flashcardSets: [FlashcardSet]

    @State private var showDocumentScanner = false
    @State private var showFileImporter = false
    @State private var showPasteTextSheet = false
    @State private var showAISettings = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var importErrorMessage = ""
    @State private var showImportAlert = false
    @State private var cameraAlertMessage = ""
    @State private var showCameraPermissionAlert = false
    @State private var showCameraSettingsAction = false
    @State private var isImporting = false
    @State private var importProgressMessage = "Analyzing your notes..."

    private var visibleFlashcardSets: [FlashcardSet] {
        FlashcardSetVisibility.visibleSets(
            flashcardSets,
            currentUserEmail: viewModel.activeSessionEmailForUI,
            totalUserCount: allUsers.count
        )
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        introCard
                        studyAreaContextCard

                        if viewModel.hasFlashcardDraft {
                            FlashcardResumeDraftCard(
                                title: viewModel.flashcardDraftTitle,
                                cardCount: viewModel.flashcardDraftCards.count
                            ) {
                                viewModel.navPath.append(NavTarget.flashcardReview)
                            }
                        }

                        VStack(spacing: 16) {
                            FlashcardActionButton(
                                icon: "doc.viewfinder",
                                title: "Scan a document",
                                subtitle: "Use your camera to capture printed notes or worksheets."
                            ) {
                                beginDocumentScan()
                            }

                            FlashcardActionButton(
                                icon: "folder",
                                title: "Choose a file",
                                subtitle: "Import a PDF, text file, or saved image from Files."
                            ) {
                                showFileImporter = true
                            }

                            FlashcardActionButton(
                                icon: "text.quote",
                                title: "Paste notes",
                                subtitle: "Paste lecture notes, summaries, or study material."
                            ) {
                                showPasteTextSheet = true
                            }

                            FlashcardActionButton(
                                icon: "rectangle.and.pencil.and.ellipsis",
                                title: "Create manually",
                                subtitle: "Write your own questions and answers from scratch."
                            ) {
                                viewModel.navPath.append(NavTarget.createFlashcardsManually)
                            }

                            FlashcardActionButton(
                                icon: "photo.on.rectangle",
                                title: "Choose an image",
                                subtitle: "Pick a photo of notes and let the app read the text."
                            ) {
                                showPhotoPicker = true
                            }
                        }

                        if isImporting {
                            ProgressView(importProgressMessage)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        savedSetsSection
                            .padding(.bottom, 110)
                    }
                    .padding(.horizontal, 25)
                    .padding(.top, 24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppTheme.surface)

            CustomNavBar(selectedTab: 1)
        }
        .navigationBarBackButtonHidden(true)
        .enableSwipeBack()
        .sheet(isPresented: $showPasteTextSheet) {
            PasteTextImportSheet { title, text in
                Task {
                    await importPastedText(title: title, text: text)
                }
            }
        }
        .sheet(isPresented: $showAISettings) {
            FlashcardAISettingsView()
        }
        .sheet(isPresented: $showDocumentScanner) {
            DocumentScannerView(
                onComplete: { images in
                    Task {
                        await importScannedImages(images)
                    }
                },
                onCancel: {
                    showDocumentScanner = false
                },
                onError: { message in
                    showDocumentScanner = false
                    presentError(message)
                }
            )
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.plainText, .utf8PlainText, .pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            handleImportedFile(result, useScannerLabel: false)
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { _, newValue in
            guard let newValue else { return }

            Task {
                await importPhoto(newValue)
                selectedPhotoItem = nil
            }
        }
        .alert("Import Failed", isPresented: $showImportAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importErrorMessage)
        }
        .alert("Camera Access Needed", isPresented: $showCameraPermissionAlert) {
            if showCameraSettingsAction {
                Button("Open Settings") {
                    openAppSettings()
                }
            }

            Button("OK", role: .cancel) { }
        } message: {
            Text(cameraAlertMessage)
        }
        .onAppear {
            viewModel.syncCurrentUserState(modelContext: modelContext)
        }
    }

    private var header: some View {
        HStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Create Flashcards")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.primary)

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                showAISettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.headline)
                    .foregroundColor(AppTheme.primary)
                    .padding(12)
                    .background(AppTheme.secondarySurface)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal)
        .padding(.top, 20)
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(introTitle, systemImage: "sparkles")
                    .font(.headline)
                    .foregroundColor(AppTheme.primary)

                Spacer()
            }

            Text(introDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(aiStatusLine)
                .font(.footnote.weight(.semibold))
                .foregroundColor(usesCloudAI ? .green : .secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.secondarySurface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var studyAreaContextCard: some View {
        if viewModel.studyAreaOptions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No studyAreas selected yet")
                    .font(.headline)
                Text("You can still create a deck now, and add studyAreas later to organize your library.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.blue.opacity(0.16), lineWidth: 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Current studyArea")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)

                Text(viewModel.defaultstudyAreaForCreation.isEmpty ? "All studyAreas" : viewModel.defaultstudyAreaForCreation)
                    .font(.headline)
                    .foregroundColor(AppTheme.text)

                Text("Imported notes will be matched against your studyAreas and you can still change the suggestion in the review step.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.blue.opacity(0.16), lineWidth: 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private var savedSetsSection: some View {
        if visibleFlashcardSets.isEmpty {
            ContentUnavailableView(
                "No Flashcard Sets Yet",
                systemImage: "square.stack.3d.up.slash",
                description: Text("Create your first deck from a document, pasted notes, or a photo.")
            )
            .padding(.top, 12)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Saved Sets")
                    .font(.headline)
                    .foregroundColor(AppTheme.primary)
                    .padding(.top, 6)

                ForEach(visibleFlashcardSets.prefix(8)) { flashcardSet in
                    NavigationLink(destination: FlashcardSetDetailView(flashcardSet: flashcardSet)) {
                        FlashcardSetCard(flashcardSet: flashcardSet)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func handleImportedFile(_ result: Result<[URL], Error>, useScannerLabel: Bool) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result {
                presentError(error.localizedDescription)
            }
            return
        }

        Task {
            await importFile(url, useScannerLabel: useScannerLabel)
        }
    }

    @MainActor
    private func beginDocumentScan() {
        guard DocumentScannerView.isSupported else {
            cameraAlertMessage = "Document scanning is not available on this device."
            showCameraSettingsAction = false
            showCameraPermissionAlert = true
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showDocumentScanner = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        showDocumentScanner = true
                    } else {
                        cameraAlertMessage = "Camera access was denied. Turn it on in Settings if you want to scan documents."
                        showCameraSettingsAction = true
                        showCameraPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            cameraAlertMessage = "Allow camera access in Settings to scan documents into flashcards."
            showCameraSettingsAction = true
            showCameraPermissionAlert = true
        @unknown default:
            cameraAlertMessage = "Camera access is not available right now."
            showCameraSettingsAction = false
            showCameraPermissionAlert = true
        }
    }

    @MainActor
    private func importFile(_ url: URL, useScannerLabel: Bool) async {
        do {
            setImportState(isLoading: true, message: "Reading your file...")
            let availablestudyAreas = viewModel.studyAreaOptions
            let preferredstudyArea = viewModel.defaultstudyAreaForCreation

            let importedContent = try await Task.detached(priority: .userInitiated) {
                if useScannerLabel {
                    return try await FlashcardImportService.importScannedDocument(from: url)
                } else {
                    return try await FlashcardImportService.importFile(from: url)
                }
            }.value

            setImportState(isLoading: true, message: activeDeckBuildMessage)
            let draftDeck: FlashcardDeckDraft = try await Task.detached(priority: .userInitiated) {
                try await FlashcardImportService.buildDraftDeck(
                    title: importedContent.title,
                    studyArea: "",
                    topic: "",
                    sourceType: importedContent.sourceType,
                    text: importedContent.text,
                    availablestudyAreas: availablestudyAreas,
                    preferredstudyArea: preferredstudyArea
                )
            }.value

            viewModel.loadFlashcardDraft(draftDeck)
            importErrorMessage = ""
            isImporting = false
            viewModel.navPath.append(NavTarget.flashcardReview)
        } catch {
            isImporting = false
            presentError(error.localizedDescription)
        }
    }

    @MainActor
    private func importScannedImages(_ images: [UIImage]) async {
        do {
            setImportState(isLoading: true, message: "Reading text from your scan...")
            showDocumentScanner = false

            let availablestudyAreas = viewModel.studyAreaOptions
            let preferredstudyArea = viewModel.defaultstudyAreaForCreation

            let importedContent = try await Task.detached(priority: .userInitiated) {
                try await FlashcardImportService.importScannedImages(images)
            }.value

            setImportState(isLoading: true, message: activeDeckBuildMessage)
            let draftDeck: FlashcardDeckDraft = try await Task.detached(priority: .userInitiated) {
                try await FlashcardImportService.buildDraftDeck(
                    title: importedContent.title,
                    studyArea: "",
                    topic: "",
                    sourceType: importedContent.sourceType,
                    text: importedContent.text,
                    availablestudyAreas: availablestudyAreas,
                    preferredstudyArea: preferredstudyArea
                )
            }.value

            viewModel.loadFlashcardDraft(draftDeck)
            importErrorMessage = ""
            isImporting = false
            viewModel.navPath.append(NavTarget.flashcardReview)
        } catch {
            isImporting = false
            presentError(error.localizedDescription)
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        do {
            await MainActor.run {
                setImportState(isLoading: true, message: "Reading text from your image...")
            }

            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw FlashcardImportError.imageLoadFailed
            }

            let importedContent = try await FlashcardImportService.importImageData(data)
            let availablestudyAreas = await MainActor.run { viewModel.studyAreaOptions }
            let preferredstudyArea = await MainActor.run { viewModel.defaultstudyAreaForCreation }

            await MainActor.run {
                setImportState(isLoading: true, message: activeImageBuildMessage)
            }

            let draftDeck: FlashcardDeckDraft = try await Task.detached(priority: .userInitiated) {
                try await FlashcardImportService.buildDraftDeck(
                    title: importedContent.title,
                    studyArea: "",
                    topic: "",
                    sourceType: importedContent.sourceType,
                    text: importedContent.text,
                    availablestudyAreas: availablestudyAreas,
                    preferredstudyArea: preferredstudyArea
                )
            }.value

            await MainActor.run {
                viewModel.loadFlashcardDraft(draftDeck)
                importErrorMessage = ""
                isImporting = false
                viewModel.navPath.append(NavTarget.flashcardReview)
            }
        } catch {
            await MainActor.run {
                isImporting = false
                presentError(error.localizedDescription)
            }
        }
    }

    private func importPastedText(title: String, text: String) async {
        do {
            let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Pasted Notes" : title
            let availablestudyAreas = await MainActor.run { viewModel.studyAreaOptions }
            let preferredstudyArea = await MainActor.run { viewModel.defaultstudyAreaForCreation }

            await MainActor.run {
                setImportState(isLoading: true, message: activePastedTextMessage)
            }

            let draftDeck: FlashcardDeckDraft = try await Task.detached(priority: .userInitiated) {
                try await FlashcardImportService.buildDraftDeck(
                    title: resolvedTitle,
                    studyArea: "",
                    topic: "",
                    sourceType: "Pasted Notes",
                    text: text,
                    availablestudyAreas: availablestudyAreas,
                    preferredstudyArea: preferredstudyArea
                )
            }.value

            await MainActor.run {
                viewModel.loadFlashcardDraft(draftDeck)
                importErrorMessage = ""
                isImporting = false
                viewModel.navPath.append(NavTarget.flashcardReview)
            }
        } catch {
            await MainActor.run {
                isImporting = false
                presentError(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func setImportState(isLoading: Bool, message: String) {
        isImporting = isLoading
        importProgressMessage = message
    }

    @MainActor
    private func presentError(_ message: String) {
        importErrorMessage = message
        showImportAlert = true
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        openURL(settingsURL)
    }

    private var usesCloudAI: Bool {
        activeAIMode != .local && FlashcardAISettingsStore.isCloudReady()
    }

    private var activeAIMode: FlashcardAIMode {
        FlashcardAISettingsStore.currentMode()
    }

    private var headerSubtitle: String {
        switch activeAIMode {
        case .local:
            return "Turn notes, files, scans, and images into editable study cards."
        case .appleIntelligence:
            return "Create source-based cards with Apple Intelligence support."
        case .openAI:
            return "Create clearer cards from your study material using AI."
        }
    }

    private var introTitle: String {
        switch activeAIMode {
        case .local:
            return "Smarter flashcard generation"
        case .appleIntelligence, .openAI:
            return "Hybrid AI flashcard generation"
        }
    }

    private var introDescription: String {
        switch activeAIMode {
        case .local:
            return "Choose how you want to add study material. You can review and edit every card before saving."
        case .appleIntelligence:
            return "Your source text is checked first, then Apple Intelligence helps improve the wording before you review the deck."
        case .openAI:
            return "Your source text is checked first, then AI helps improve question quality before you review the deck."
        }
    }

    private var aiStatusLine: String {
        FlashcardAISettingsStore.statusText()
    }

    private var activeDeckBuildMessage: String {
        guard usesCloudAI else {
            return "Building stronger study flashcards..."
        }

        switch activeAIMode {
        case .local:
            return "Building stronger study flashcards..."
        case .appleIntelligence:
            return "Building flashcards with Apple Intelligence..."
        case .openAI:
            return "Building grounded AI flashcards..."
        }
    }

    private var activeImageBuildMessage: String {
        guard usesCloudAI else {
            return "Creating stronger flashcards..."
        }

        switch activeAIMode {
        case .local:
            return "Creating stronger flashcards..."
        case .appleIntelligence:
            return "Creating flashcards with Apple Intelligence..."
        case .openAI:
            return "Creating grounded AI flashcards..."
        }
    }

    private var activePastedTextMessage: String {
        guard usesCloudAI else {
            return "Analyzing your pasted notes..."
        }

        switch activeAIMode {
        case .local:
            return "Analyzing your pasted notes..."
        case .appleIntelligence:
            return "Turning your notes into an Apple Intelligence deck..."
        case .openAI:
            return "Turning your notes into a grounded AI deck..."
        }
    }
}

struct FlashcardSetCard: View {
    let flashcardSet: FlashcardSet

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 54, height: 54)

                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundColor(AppTheme.primary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(flashcardSet.title)
                    .font(.headline)
                    .foregroundColor(AppTheme.text)
                    .multilineTextAlignment(.leading)

                Text("\(flashcardSet.cards.count) cards")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(setSubtitle)
                    .font(.caption)
                    .foregroundColor(AppTheme.primary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .padding(.top, 6)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(AppTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.18), lineWidth: 1.5)
        )
        .cornerRadius(16)
    }

    private var setSubtitle: String {
        [flashcardSet.studyArea, flashcardSet.sourceType]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}

struct FlashcardResumeDraftCard: View {
    let title: String
    let cardCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Continue Editing")
                        .font(.headline)
                        .foregroundColor(AppTheme.text)

                    Text("\(resolvedTitle) • \(cardCount) draft cards")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundColor(AppTheme.primary)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(AppTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.blue.opacity(0.25), lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }

    private var resolvedTitle: String {
        title.isEmpty ? "Untitled Deck" : title
    }
}

struct FlashcardActionButton: View {
    var icon: String
    var title: String
    var subtitle: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            FlashcardActionRow(icon: icon, title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }
}

struct FlashcardActionRow: View {
    var icon: String
    var title: String
    var subtitle: String

    var body: some View {
        HStack(spacing: 15) {
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.primary.opacity(0.12))
                .frame(width: 54, height: 54)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(AppTheme.primary)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(AppTheme.text)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.secondaryText)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundColor(AppTheme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(AppTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppTheme.subtleBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct PasteTextImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var pastedText = ""

    let onGenerate: (String, String) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Paste your notes, summary, or study guide here. The app will turn them into editable flashcards.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Deck Title")
                        .font(.headline)
                    TextField("For example: Climate Action Notes", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.headline)

                    TextEditor(text: $pastedText)
                        .frame(minHeight: 220)
                        .padding(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.blue.opacity(0.25), lineWidth: 1.2)
                        )
                }

                Spacer()

                Button {
                    onGenerate(title, pastedText)
                    dismiss()
                } label: {
                    Text("Generate Flashcards")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppTheme.primarySoft)
                        .clipShape(Capsule())
                }
                .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }
            .padding(24)
            .navigationTitle("Paste Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}

#Preview {
    NavigationStack {
        CreateFlashCardView()
            .environment(AppViewModel())
    }
}
