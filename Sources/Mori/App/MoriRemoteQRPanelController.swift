import AppKit
import CoreImage
import MoriCore
import MoriTerminal
import SwiftUI

// MARK: - QR image

enum MoriRemoteQRImage {
    /// Renders a QR code suitable for display using nearest-neighbor scaling
    /// so module edges stay sharp and scannable.
    static func nsImage(for string: String, pixelWidth: Int = 1024) -> NSImage? {
        let data = Data(string.utf8)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }

        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }

        let scale = max(1, pixelWidth / cgImage.width)
        let w = cgImage.width * scale
        let h = cgImage.height * scale

        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: w, height: h,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        ctx.interpolationQuality = .none
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let scaled = ctx.makeImage() else { return nil }
        return NSImage(cgImage: scaled, size: NSSize(width: w, height: h))
    }
}

// MARK: - SwiftUI content

private struct MoriRemoteQRPanelRootView: View {
    @Bindable var appState: AppState
    let projectId: UUID
    let onClose: () -> Void
    @State private var includePassword = false
    @State private var qrString: String = ""
    @State private var qrImage: NSImage?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String.localized("Scan this code with MoriRemote on your iPhone or iPad to add this server."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let nsImage = qrImage {
                Image(nsImage: nsImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(minWidth: 360, idealWidth: 420, maxWidth: 520, minHeight: 360, idealHeight: 420, maxHeight: 520)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(String.localized("MoriRemote configuration QR code"))
                    .id(qrString)
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }

            Toggle(
                String.localized("Include password in QR code"),
                isOn: Binding(
                    get: { includePassword },
                    set: { newValue in
                        includePassword = newValue
                        refreshQR()
                    }
                )
            )
            .help(String.localized("Anyone who can see the QR code can read the password. Use only in private."))

            if includePassword {
                Text(String.localized("Warning: the password is embedded in the QR code as plain text. Do not share screenshots or display this in public."))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(String.localized("MoriRemote supports password authentication. If this host uses SSH keys only, you must add the server manually on the device."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(String.localized("Copy QR Text")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(qrString, forType: .string)
                }
                .disabled(qrString.isEmpty)

                Spacer()

                Button(String.localized("Close")) {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(minWidth: 440)
        .onAppear { refreshQR() }
    }

    private func refreshQR() {
        errorMessage = nil
        do {
            let payload = try MoriRemoteTransferExport.makePayload(
                appState: appState,
                projectId: projectId,
                includePassword: includePassword
            )
            qrString = try payload.encodeToQRString()
            qrImage = MoriRemoteQRImage.nsImage(for: qrString)
        } catch {
            errorMessage = error.localizedDescription
            qrString = ""
            qrImage = nil
        }
    }
}

// MARK: - Panel controller

@MainActor
final class MoriRemoteQRPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?

    func present(appState: AppState, projectId: UUID, themeInfo: GhosttyThemeInfo) {
        panel?.close()
        panel = nil

        let contentRect = NSRect(x: 0, y: 0, width: 500, height: 680)
        let styleMask: NSWindow.StyleMask = [.titled, .closable]
        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        panel.title = String.localized("MoriRemote QR Code")
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()
        panel.minSize = NSSize(width: 440, height: 560)

        applyTheme(panel, themeInfo: themeInfo)

        let root = MoriRemoteQRPanelRootView(
            appState: appState,
            projectId: projectId,
            onClose: { [weak panel] in
                panel?.close()
            }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = NSView(frame: contentRect)
        wrapper.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: wrapper.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        panel.contentView = wrapper
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    func updateAppearance(themeInfo: GhosttyThemeInfo) {
        guard let panel else { return }
        applyTheme(panel, themeInfo: themeInfo)
    }

    private func applyTheme(_ panel: NSWindow, themeInfo: GhosttyThemeInfo) {
        panel.appearance = NSAppearance(named: themeInfo.isDark ? .darkAqua : .aqua)
        panel.backgroundColor = themeInfo.background
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
    }
}
