import SwiftUI
import AVFoundation

/// QR code scanner view using AVCaptureSession.
/// Scans for `mori-relay://<host>/<token>` URLs to pair with a Mac.
/// Includes a manual URL entry fallback for simulator testing.
struct QRScannerView: View {
    let onScanned: (String) -> Void

    @State private var showManualEntry = false
    @State private var manualURL = ""
    @State private var cameraPermissionDenied = false
    @State private var scannedCode: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Header
                VStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 64))
                        .foregroundStyle(.white)
                    Text("Scan QR Code")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text("Scan the QR code shown on your Mac\nto pair with Mori Remote")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                }

                // Camera preview or permission prompt
                if cameraPermissionDenied {
                    cameraPermissionView
                } else {
                    CameraPreviewView(onCodeScanned: handleScan)
                        .frame(width: 280, height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.white.opacity(0.3), lineWidth: 2)
                        )
                }

                Spacer()

                // Manual entry button (simulator fallback)
                Button {
                    showManualEntry = true
                } label: {
                    Label("Enter URL Manually", systemImage: "keyboard")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.bottom, 32)
            }
            .padding()
        }
        .sheet(isPresented: $showManualEntry) {
            ManualURLEntryView(
                url: $manualURL,
                onSubmit: { url in
                    showManualEntry = false
                    onScanned(url)
                }
            )
        }
        .task {
            await checkCameraPermission()
        }
    }

    private var cameraPermissionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.gray)
            Text("Camera Access Required")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Open Settings to allow camera access\nfor QR code scanning")
                .font(.subheadline)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(width: 280, height: 280)
    }

    private func checkCameraPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .denied, .restricted:
            cameraPermissionDenied = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraPermissionDenied = !granted
        case .authorized:
            cameraPermissionDenied = false
        @unknown default:
            break
        }
    }

    private func handleScan(_ code: String) {
        // Prevent duplicate scans
        guard scannedCode == nil else { return }
        scannedCode = code
        onScanned(code)
    }
}

// MARK: - Camera Preview (AVCaptureSession)

/// UIViewRepresentable wrapping AVCaptureSession for QR code scanning.
private struct CameraPreviewView: UIViewRepresentable {
    let onCodeScanned: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned)
    }

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.coordinator = context.coordinator
        view.startScanning()
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onCodeScanned: (String) -> Void
        private var hasScanned = false

        init(onCodeScanned: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
        }

        nonisolated func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard let readableObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let stringValue = readableObject.stringValue else {
                return
            }

            // Only accept mori-relay:// URLs
            guard stringValue.hasPrefix("mori-relay://") else { return }

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard !self.hasScanned else { return }
                    self.hasScanned = true
                    AudioServicesPlaySystemSound(SystemSoundServices.vibrate)
                    self.onCodeScanned(stringValue)
                }
            }
        }
    }
}

/// Sendable wrapper for AVCaptureSession to cross isolation boundaries.
private struct SendableAVCaptureSession: @unchecked Sendable {
    let session: AVCaptureSession
    init(_ session: AVCaptureSession) { self.session = session }
}

/// System sound for haptic feedback on scan.
private enum SystemSoundServices {
    static let vibrate: SystemSoundID = 4095
}

/// UIView hosting the AVCaptureSession preview layer.
@MainActor
private final class CameraPreviewUIView: UIView {
    var coordinator: CameraPreviewView.Coordinator?
    private var captureSession: AVCaptureSession?

    func startScanning() {
        let session = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice),
              session.canAddInput(videoInput) else {
            NSLog("[QRScanner] Camera not available")
            return
        }

        session.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            NSLog("[QRScanner] Cannot add metadata output")
            return
        }

        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(coordinator, queue: DispatchQueue.main)
        metadataOutput.metadataObjectTypes = [.qr]

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = bounds
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)

        self.captureSession = session

        // Start on background thread — use nonisolated wrapper to avoid sending MainActor-isolated capture
        let sendableSession = SendableAVCaptureSession(session)
        Task.detached {
            sendableSession.session.startRunning()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let previewLayer = layer.sublayers?.first(where: { $0 is AVCaptureVideoPreviewLayer }) {
            previewLayer.frame = bounds
        }
    }
}

// MARK: - Manual URL Entry

/// Fallback for simulator testing — manually enter the relay URL.
private struct ManualURLEntryView: View {
    @Binding var url: String
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Enter Relay URL")
                    .font(.headline)
                    .padding(.top)

                Text("Format: mori-relay://host/token")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("mori-relay://relay.example.com/abc123", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal)

                Button("Connect") {
                    guard !url.isEmpty else { return }
                    onSubmit(url)
                }
                .buttonStyle(.borderedProminent)
                .disabled(url.isEmpty)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
