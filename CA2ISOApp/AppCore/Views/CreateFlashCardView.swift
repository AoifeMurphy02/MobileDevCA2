//
//  CreateFlashCardView.swift
//  CA2ISOApp
//
//  Created by Aoife on 06/04/2026.
//

import Foundation
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct CreateFlashCardView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Query(sort: \FlashcardSet.createdAt, order: .reverse) private var flashcardSets: [FlashcardSet]

    @State private var showScanImporter = false
    @State private var showFileImporter = false
    @State private var showPasteTextSheet = false
    @State private var showAISettings = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var importErrorMessage = ""
    @State private var showImportAlert = false
    @State private var isImporting = false
    @State private var importProgressMessage = "Analyzing your notes..."

    var body: some View {
        @Bindable var viewModel = viewModel

        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        introCard
                        studySubjectContextCard

                        if viewModel.hasFlashcardDraft {
                            FlashcardResumeDraftCard(
                                title: viewModel.flashcardDraftTitle,
                                cardCount: viewModel.flashcardDraftCards.count
                            ) {
                                viewModel.navPath.append(NavTarget.flashcardReview)
                            }
                        }

                        VStack(spacing: 16) {
                            FlashcardActionButton(icon: "camera", title: "Scan document") {
                                showScanImporter = true
                            }

                            FlashcardActionButton(icon: "paperclip", title: "Select file") {
                                showFileImporter = true
                            }

                            FlashcardActionButton(icon: "doc.text", title: "Paste text") {
                                showPasteTextSheet = true
                            }

                            FlashcardActionButton(icon: "square.and.pencil", title: "Create manually") {
                                viewModel.navPath.append(NavTarget.createFlashcardsManually)
                            }

                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                FlashcardActionRow(icon: "photo", title: "Select image")
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
            .background(Color.white)

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
        .fileImporter(
            isPresented: $showScanImporter,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            handleImportedFile(result, useScannerLabel: true)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.plainText, .utf8PlainText, .pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            handleImportedFile(result, useScannerLabel: false)
        }
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
    }

    private var header: some View {
        HStack(spacing: 15) {
            Circle()
                .fill(.gray.opacity(0.3))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundColor(.white)
                )
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Create Flashcards")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.11, green: 0.49, blue: 0.95))

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
                    .foregroundColor(Color(red: 0.11, green: 0.49, blue: 0.95))
                    .padding(12)
                    .background(Color(red: 0.94, green: 0.97, blue: 1.0))
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
                    .foregroundColor(Color(red: 0.11, green: 0.49, blue: 0.95))

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
        .background(Color(red: 0.94, green: 0.97, blue: 1.0))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var studySubjectContextCard: some View {
        if viewModel.studySubjectOptions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No studySubjects selected yet")
                    .font(.headline)
                Text("You can still create a deck now, and add studySubjects later to organize your library.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.blue.opacity(0.16), lineWidth: 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Current studySubject")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)

                Text(viewModel.defaultstudySubjectForCreation.isEmpty ? "All studySubjects" : viewModel.defaultstudySubjectForCreation)
                    .font(.headline)
                    .foregroundColor(.black)

                Text("Imported notes will be matched against your studySubjects and you can still change the suggestion in the review step.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.blue.opacity(0.16), lineWidth: 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private var savedSetsSection: some View {
        if flashcardSets.isEmpty {
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
                    .foregroundColor(Color(red: 0.11, green: 0.49, blue: 0.95))
                    .padding(.top, 6)

                ForEach(flashcardSets.prefix(8)) { flashcardSet in
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
    private func importFile(_ url: URL, useScannerLabel: Bool) async {
        do {
            setImportState(isLoading: true, message: "Reading your file...")
            let availablestudySubjects = viewModel.studySubjectOptions
            let preferredstudySubject = viewModel.defaultstudySubjectForCreation

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
                    studySubject: "",
                    topic: "",
                    sourceType: importedContent.sourceType,
                    text: importedContent.text,
                    availablestudySubjects: availablestudySubjects,
                    preferredstudySubject: preferredstudySubject
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
            let availablestudySubjects = await MainActor.run { viewModel.studySubjectOptions }
            let preferredstudySubject = await MainActor.run { viewModel.defaultstudySubjectForCreation }

            await MainActor.run {
                setImportState(isLoading: true, message: activeImageBuildMessage)
            }

            let draftDeck: FlashcardDeckDraft = try await Task.detached(priority: .userInitiated) {
                try await FlashcardImportService.buildDraftDeck(
                    title: importedContent.title,
                    studySubject: "",
                    topic: "",
                    sourceType: importedContent.sourceType,
                    text: importedContent.text,
                    availablestudySubjects: availablestudySubjects,
                    preferredstudySubject: preferredstudySubject
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
            let availablestudySubjects = await MainActor.run { viewModel.studySubjectOptions }
            let preferredstudySubject = await MainActor.run { viewModel.defaultstudySubjectForCreation }

            await MainActor.run {
                setImportState(isLoading: true, message: activePastedTextMessage)
            }

            let draftDeck: FlashcardDeckDraft = try await Task.detached(priority: .userInitiated) {
                try await FlashcardImportService.buildDraftDeck(
                    title: resolvedTitle,
                    studySubject: "",
                    topic: "",
                    sourceType: "Pasted Notes",
                    text: text,
                    availablestudySubjects: availablestudySubjects,
                    preferredstudySubject: preferredstudySubject
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

    private var usesCloudAI: Bool {
        activeAIMode != .local && FlashcardAISettingsStore.isCloudReady()
    }

    private var activeAIMode: FlashcardAIMode {
        FlashcardAISettingsStore.currentMode()
    }

    private var headerSubtitle: String {
        switch activeAIMode {
        case .local:
            return "Stronger on-device AI for notes, files, scans, and images."
        case .appleIntelligence:
            return "Grounded flashcards with Apple Intelligence on device."
        case .openAI:
            return "Grounded AI plus OpenAI for files, scans, images, and pasted notes."
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
            return "The app filters weak source text, ranks stronger concepts, suggests a studySubject and topic, and turns your material into cleaner question-and-answer flashcards before you review the deck."
        case .appleIntelligence:
            return "The app grounds itself in your source text first, then uses Apple Intelligence on device to improve card quality, coverage, and phrasing while keeping the local fallback."
        case .openAI:
            return "The app now grounds itself in your source text first, then uses OpenAI to improve question quality, card coverage, and follow-up chat support without dropping the local fallback."
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
                    .foregroundColor(Color(red: 0.11, green: 0.49, blue: 0.95))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(flashcardSet.title)
                    .font(.headline)
                    .foregroundColor(.black)
                    .multilineTextAlignment(.leading)

                Text("\(flashcardSet.cards.count) cards")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(setSubtitle)
                    .font(.caption)
                    .foregroundColor(Color(red: 0.11, green: 0.49, blue: 0.95))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .padding(.top, 6)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.18), lineWidth: 1.5)
        )
        .cornerRadius(16)
    }

    private var setSubtitle: String {
        [flashcardSet.studySubject, flashcardSet.sourceType]
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
                        .foregroundColor(.black)

                    Text("\(resolvedTitle) • \(cardCount) draft cards")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundColor(Color(red: 0.11, green: 0.49, blue: 0.95))
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color(red: 0.97, green: 0.99, blue: 1.0))
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
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            FlashcardActionRow(icon: icon, title: title)
        }
    }
}

struct FlashcardActionRow: View {
    var icon: String
    var title: String

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 30)

            Text(title)
                .font(.system(size: 18, weight: .bold))

            Spacer()
        }
        .foregroundColor(.black)
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.4), lineWidth: 1.5)
        )
        .background(Color.white)
        .cornerRadius(12)
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
                        .background(Color(red: 0.25, green: 0.53, blue: 0.94))
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
