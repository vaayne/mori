import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

private struct GhosttyStagedImage: Transferable, Sendable {
    let url: URL
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let source = received.file
            let filename = sanitizedFilename(source.lastPathComponent)
            let destination = try stagingURL(filename: filename)
            try FileManager.default.copyItem(at: source, to: destination)
            return GhosttyStagedImage(url: destination, filename: filename)
        }
    }

    static func fromPasteboard() throws -> GhosttyStagedImage {
        guard let image = UIPasteboard.general.image,
              let data = image.pngData()
        else { throw GhosttyImageAttachmentError.noPasteboardImage }
        let filename = "pasted-image.png"
        let destination = try stagingURL(filename: filename)
        try data.write(to: destination, options: .atomic)
        return GhosttyStagedImage(url: destination, filename: filename)
    }

    private static func stagingURL(filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MoriRemoteImages", isDirectory: true)
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(filename, isDirectory: false)
    }

    private static func sanitizedFilename(_ value: String) -> String {
        let cleaned = value.unicodeScalars.map { scalar -> Character in
            scalar.value < 0x20 || scalar == "/" || scalar == "\\" || scalar == "\0"
                ? "_" : Character(scalar)
        }
        let filename = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        return filename.isEmpty ? "image" : String(filename.prefix(180))
    }
}

enum GhosttyImageTerminalPathFormatter {
    static func insertionText(for path: String) -> String? {
        guard !path.isEmpty,
              !path.unicodeScalars.contains(where: { $0 == "\0" || $0 == "\n" || $0 == "\r" })
        else { return nil }
        if path.unicodeScalars.allSatisfy({ shellSafe.contains($0) }) { return path }
        if path.hasPrefix("~/") {
            return "~/" + singleQuote(String(path.dropFirst(2)))
        }
        return singleQuote(path)
    }

    private static func singleQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private static let shellSafe = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./~-"
    )
}

private enum GhosttyImageAttachmentError: LocalizedError {
    case noPasteboardImage
    case photoUnavailable
    case invalidRemotePath
    case terminalRejected

    var errorDescription: String? {
        switch self {
        case .noPasteboardImage: String(localized: "The clipboard does not contain an image.")
        case .photoUnavailable: String(localized: "The selected image could not be loaded.")
        case .invalidRemotePath: String(localized: "The uploaded image path is invalid.")
        case .terminalRejected: String(localized: "The terminal could not insert the image path.")
        }
    }
}

struct GhosttyImageAttachmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let uploader: MoriRemoteTerminalImageUploader
    let insertPath: (String) -> Bool

    @State private var photoSelection: PhotosPickerItem?
    @State private var stagedImage: GhosttyStagedImage?
    @State private var previewImage: UIImage?
    @State private var isPreparing = false
    @State private var isUploading = false
    @State private var uploadedBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var errorMessage: String?
    @State private var preparationTask: Task<Void, Never>?
    @State private var uploadTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                preview

                HStack(spacing: 10) {
                    PhotosPicker(selection: $photoSelection, matching: .images) {
                        Label(String(localized: "Choose photo"), systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isUploading)

                    Button(action: pasteImage) {
                        Label(String(localized: "Paste image"), systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isUploading)
                }

                if isUploading {
                    ProgressView(value: uploadFraction) {
                        Text(String(localized: "Uploading image…"))
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle(String(localized: "Image"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Insert path"), action: uploadAndInsert)
                        .disabled(stagedImage == nil || isPreparing || isUploading)
                }
            }
        }
        .onChange(of: photoSelection) { _, selection in
            guard let selection else { return }
            prepare(selection)
        }
        .onDisappear {
            preparationTask?.cancel()
            uploadTask?.cancel()
            if !isUploading { cleanup(stagedImage) }
        }
    }

    @ViewBuilder private var preview: some View {
        if let previewImage {
            Image(uiImage: previewImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12))
                }
        } else if isPreparing {
            ProgressView(String(localized: "Loading image…"))
                .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            ContentUnavailableView(
                String(localized: "Choose an image"),
                systemImage: "photo",
                description: Text(String(localized: "The image is uploaded through the current SSH server, then its remote path is inserted into the terminal."))
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        }
    }

    private var uploadFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(uploadedBytes) / Double(totalBytes)))
    }

    private func prepare(_ selection: PhotosPickerItem) {
        preparationTask?.cancel()
        isPreparing = true
        errorMessage = nil
        preparationTask = Task {
            do {
                guard let image = try await selection.loadTransferable(type: GhosttyStagedImage.self) else {
                    throw GhosttyImageAttachmentError.photoUnavailable
                }
                do {
                    try Task.checkCancellation()
                    let preview = await Task.detached(priority: .utility) { UIImage(contentsOfFile: image.url.path) }.value
                    try Task.checkCancellation()
                    await MainActor.run {
                        cleanup(stagedImage)
                        stagedImage = image
                        previewImage = preview
                        photoSelection = nil
                        isPreparing = false
                    }
                } catch {
                    cleanup(image)
                    throw error
                }
            } catch is CancellationError {
                await MainActor.run {
                    photoSelection = nil
                    isPreparing = false
                }
            } catch {
                await MainActor.run {
                    photoSelection = nil
                    isPreparing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func pasteImage() {
        preparationTask?.cancel()
        isPreparing = false
        do {
            let image = try GhosttyStagedImage.fromPasteboard()
            cleanup(stagedImage)
            stagedImage = image
            previewImage = UIImage(contentsOfFile: image.url.path)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uploadAndInsert() {
        guard let stagedImage else { return }
        isUploading = true
        errorMessage = nil
        uploadedBytes = 0
        totalBytes = (try? FileManager.default.attributesOfItem(atPath: stagedImage.url.path)[.size] as? NSNumber)?.int64Value ?? 0
        let expectedBytes = totalBytes
        uploadTask = Task {
            do {
                let remotePath = try await uploader.upload(
                    localURL: stagedImage.url,
                    filename: stagedImage.filename,
                    progress: { uploaded, total in
                        await MainActor.run {
                            uploadedBytes = uploaded
                            totalBytes = total > 0 ? total : expectedBytes
                        }
                    }
                )
                try Task.checkCancellation()
                guard let insertion = GhosttyImageTerminalPathFormatter.insertionText(for: remotePath) else {
                    throw GhosttyImageAttachmentError.invalidRemotePath
                }
                guard insertPath(insertion) else { throw GhosttyImageAttachmentError.terminalRejected }
                await MainActor.run {
                    cleanup(stagedImage)
                    isUploading = false
                    self.stagedImage = nil
                    dismiss()
                }
            } catch is CancellationError {
                await MainActor.run {
                    cleanup(stagedImage)
                    isUploading = false
                    self.stagedImage = nil
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func cleanup(_ image: GhosttyStagedImage?) {
        guard let image else { return }
        try? FileManager.default.removeItem(at: image.url.deletingLastPathComponent())
    }
}
