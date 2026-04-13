#if os(iOS)
@preconcurrency import AVFoundation
import SwiftUI
import UIKit

// MARK: - Dimmed overlay with transparent cutout

private final class QRScanMaskView: UIView {
    var cutoutRect: CGRect = .zero {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.52).cgColor)
        ctx.fill(bounds)
        ctx.setBlendMode(.clear)
        ctx.setFillColor(UIColor.clear.cgColor)
        let path = UIBezierPath(roundedRect: cutoutRect, cornerRadius: 14)
        ctx.addPath(path.cgPath)
        ctx.fillPath()

        ctx.setBlendMode(.normal)
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.85).cgColor)
        ctx.setLineWidth(2)
        ctx.addPath(UIBezierPath(roundedRect: cutoutRect, cornerRadius: 14).cgPath)
        ctx.strokePath()
    }
}

/// Camera QR scanner. Calls `onScan` once with the first decoded string, then stops.
struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.coordinator = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
        let onScan: (String) -> Void
        let onCancel: () -> Void
        weak var session: AVCaptureSession?
        // Safe: delegate is dispatched on main queue only (see setupCapture)
        private var didEmit = false

        init(onScan: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !didEmit,
                  let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  obj.type == .qr,
                  let value = obj.stringValue,
                  !value.isEmpty
            else { return }
            didEmit = true
            // stopRunning() blocks; finish teardown off the main thread before dismissing the sheet
            // so SwiftUI transition is not stalled by viewWillDisappear also calling stop on main.
            let sessionToStop = session
            let decoded = value
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                if let sessionToStop, sessionToStop.isRunning {
                    sessionToStop.stopRunning()
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.onScan(decoded)
                }
            }
        }
    }
}

final class ScannerViewController: UIViewController {
    fileprivate var coordinator: QRScannerView.Coordinator?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var metadataOutput: AVCaptureMetadataOutput?
    private var captureDevice: AVCaptureDevice?
    private let maskView = QRScanMaskView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCapture()
                    } else {
                        self?.showDenied()
                    }
                }
            }
        default:
            showDenied()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let sess = session
        guard sess.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            sess.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        updateCutoutAndMetadataRect()
    }

    private func updateCutoutAndMetadataRect() {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }

        let side = min(bounds.width, bounds.height) * 0.72
        let cutout = CGRect(
            x: (bounds.width - side) / 2,
            y: (bounds.height - side) / 2 - bounds.height * 0.04,
            width: side,
            height: side
        )
        maskView.cutoutRect = cutout
        maskView.setNeedsDisplay()

        // rectOfInterest requires an active session connection to convert coordinates
        // correctly. Only restrict the scan region once the session is running;
        // before that, keep the default (full frame) so detection always works.
        guard let preview = previewLayer, let output = metadataOutput,
              session.isRunning else { return }
        let interest = preview.metadataOutputRectConverted(fromLayerRect: cutout)
        guard !interest.isEmpty else { return }
        output.rectOfInterest = interest
    }

    private func setupCapture() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            showUnavailable()
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        captureDevice = device

        configureDeviceForScanning(device)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            showUnavailable()
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        coordinator?.session = session
        output.setMetadataObjectsDelegate(coordinator, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.qr]
        metadataOutput = output

        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        if let conn = preview.connection {
            if #available(iOS 17.0, *) {
                let angle: CGFloat = 90
                if conn.isVideoRotationAngleSupported(angle) {
                    conn.videoRotationAngle = angle
                }
            } else if conn.isVideoOrientationSupported {
                conn.videoOrientation = .portrait
            }
        }
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview

        maskView.translatesAutoresizingMaskIntoConstraints = false
        maskView.isUserInteractionEnabled = false
        view.addSubview(maskView)
        NSLayoutConstraint.activate([
            maskView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            maskView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            maskView.topAnchor.constraint(equalTo: view.topAnchor),
            maskView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let cancel = makeCancelButton()
        view.addSubview(cancel)
        NSLayoutConstraint.activate([
            cancel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
        ])

        updateCutoutAndMetadataRect()

        let sess = session
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            sess.startRunning()
            DispatchQueue.main.async {
                self?.updateCutoutAndMetadataRect()
            }
        }
    }

    private func configureDeviceForScanning(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isLowLightBoostSupported {
                device.automaticallyEnablesLowLightBoostWhenAvailable = true
            }
        } catch {
            print("QRScanner: device configuration failed: \(error)")
        }
    }

    private func showDenied() {
        let label = makeLabel(text: String.localized("Camera access is required to scan QR codes. You can enable it in Settings."))
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        let settings = UIButton(type: .system)
        settings.translatesAutoresizingMaskIntoConstraints = false
        settings.setTitle(String.localized("Open Settings"), for: .normal)
        settings.addAction(UIAction { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }, for: .touchUpInside)
        view.addSubview(settings)
        NSLayoutConstraint.activate([
            settings.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 16),
            settings.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        addCancelButton()
    }

    private func showUnavailable() {
        let label = makeLabel(text: String.localized("Camera is not available on this device."))
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        addCancelButton()
    }

    private func makeLabel(text: String) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 16)
        return label
    }

    private func makeCancelButton() -> UIButton {
        let cancel = UIButton(type: .system)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.setTitle(String.localized("Cancel"), for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        cancel.tintColor = .white
        cancel.addAction(UIAction { [weak self] _ in
            self?.coordinator?.onCancel()
        }, for: .touchUpInside)
        return cancel
    }

    private func addCancelButton() {
        let cancel = makeCancelButton()
        view.addSubview(cancel)
        NSLayoutConstraint.activate([
            cancel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])
    }
}
#endif
