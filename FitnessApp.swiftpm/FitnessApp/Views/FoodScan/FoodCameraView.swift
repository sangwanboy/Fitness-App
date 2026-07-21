import SwiftUI
import AVFoundation
import PhotosUI

// MARK: - Live camera panel for meal scanning
//
// Opens straight to the viewfinder. A centered shutter captures a still;
// an "Upload" button sits at the lower-left of the shutter for picking an
// existing photo. Returns the chosen UIImage via `onImage`.

struct FoodCameraView: View {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void
    /// Fired once with a detected barcode/GTIN string. Optional so existing
    /// call sites that only want photo capture stay unchanged.
    var onBarcode: ((String) -> Void)? = nil

    @StateObject private var cam = FoodCameraModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var photoItem: PhotosPickerItem? = nil
    /// Debounce: once a code is handled we ignore further reads until the view
    /// reappears (reset in onAppear).
    @State private var scanned = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Live preview (or a state message when the camera isn't usable)
            switch cam.state {
            case .ready:
                CameraPreview(session: cam.session)
                    .ignoresSafeArea()
            case .configuring:
                ProgressView().tint(.white)
            case .denied:
                stateMessage(icon: "lock.fill",
                             title: "Camera access is off",
                             body: "Enable camera access in Settings, or upload a photo from your library below.",
                             showSettings: true)
            case .unavailable:
                stateMessage(icon: "camera.fill",
                             title: "Camera unavailable",
                             body: "No camera on this device. Upload a photo from your library below.",
                             showSettings: false)
            case .failed(let reason):
                stateMessage(icon: "exclamationmark.triangle.fill",
                             title: "Camera didn't start",
                             body: reason + " You can also upload a photo from your library below.",
                             showSettings: false,
                             retry: { cam.start() })
            }

            // Overlay chrome
            VStack(spacing: 0) {
                topBar
                Spacer()
                if cam.state == .ready {
                    VStack(spacing: 8) {
                        Text("Center your meal in the frame")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.35), in: Capsule())

                        Label("Point at a barcode to scan a product", systemImage: "barcode.viewfinder")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.bottom, 16)
                }
                bottomControls
            }
        }
        .onAppear {
            cam.onCapture = { img in onImage(img) }
            // Reset the debounce so scanning resumes whenever we return to the
            // camera (e.g. "Scan again" after a failed lookup).
            scanned = false
            cam.onBarcode = { code in
                guard !scanned else { return }
                scanned = true
                // Success haptic on a real detection.
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onBarcode?(code)
            }
            cam.start()
        }
        .onDisappear { cam.stop() }
        // Belt-and-braces: releasing the camera must not depend on
        // onDisappear alone — backgrounding with the scanner open must
        // drop the session (and its green status-bar indicator) too.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { cam.stop() }
            else if phase == .active && cam.state == .ready { cam.start() }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    // Decode off the main actor — UIImage(data:) on a full-res
                    // library photo can block the UI for tens of ms.
                    let img = await Task.detached(priority: .userInitiated) {
                        UIImage(data: data)
                    }.value
                    if let img { onImage(img) }
                }
                photoItem = nil
            }
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button { onCancel() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.4), in: Circle())
            }
            Spacer()
            Text("Scan Meal")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var bottomControls: some View {
        ZStack {
            // Shutter — centered
            Button { cam.capture() } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 5).frame(width: 74, height: 74)
                    Circle().fill(.white).frame(width: 60, height: 60)
                }
            }
            .disabled(cam.state != .ready)
            .opacity(cam.state == .ready ? 1 : 0.35)

            // Upload from photos — lower-left of the shutter
            HStack {
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    VStack(spacing: 5) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 52, height: 52)
                            .glassEffect(.regular.tint(.white.opacity(0.18)), in: .rect(cornerRadius: 14))
                        Text("Upload")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 32)
        }
        .padding(.bottom, 28)
    }

    private func stateMessage(icon: String, title: String, body: String, showSettings: Bool,
                              retry: (() -> Void)? = nil) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.85))
            Text(title)
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(.white)
            Text(body)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            if let retry {
                Button("Try again", action: retry)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.15), in: Capsule())
            }
            if showSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(.white.opacity(0.18), in: Capsule())
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Camera session

final class FoodCameraModel: NSObject, ObservableObject {
    enum CamState: Equatable { case configuring, ready, denied, unavailable, failed(String) }

    @Published var state: CamState = .configuring

    // Session/queue are recreated on retry after a hang: AVCaptureSession's
    // startRunning is synchronous and CAN block indefinitely (hardware
    // contention/interruption — seen live: infinite spinner, and the later
    // stop() queued behind the hang so the green camera indicator persisted
    // on Home after the scanner closed). A poisoned pair is abandoned, never
    // reused.
    private(set) var session = AVCaptureSession()
    private var output = AVCapturePhotoOutput()
    private var metadataOutput = AVCaptureMetadataOutput()
    private var queue = DispatchQueue(label: "fitnessapp.food.camera")
    private var configured = false
    private var poisoned = false
    private var watchdog: Task<Void, Never>?
    private var sessionObservers: [NSObjectProtocol] = []
    /// Identifies the current start attempt. A hung attempt that unblocks
    /// AFTER a retry rebuilt the session must not touch state (the poisoned
    /// flag alone can't protect — a retry resets it).
    private var attemptID = UUID()

    /// Called on the main thread with the captured/normalised still.
    var onCapture: ((UIImage) -> Void)?
    /// Called on the main thread with a detected barcode/GTIN string.
    var onBarcode: ((String) -> Void)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            if poisoned { rebuildSessionObjects() }
            state = .configuring
            armWatchdog()
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.armWatchdog()
                        self.configureAndRun()
                    } else { self.state = .denied }
                }
            }
        default:
            state = .denied
        }
    }

    /// Abandon a queue whose startRunning hung and start clean — enqueueing
    /// anything else behind a blocked serial queue would never run.
    private func rebuildSessionObjects() {
        sessionObservers.forEach { NotificationCenter.default.removeObserver($0) }
        sessionObservers = []
        // Enqueue a stop for the abandoned pair on ITS OWN queue: it runs the
        // moment the hung startRunning finally unblocks, so the orphaned
        // session can't keep the camera (green indicator) alive forever.
        let oldSession = session
        queue.async { if oldSession.isRunning { oldSession.stopRunning() } }
        session = AVCaptureSession()
        output = AVCapturePhotoOutput()
        metadataOutput = AVCaptureMetadataOutput()
        queue = DispatchQueue(label: "fitnessapp.food.camera.\(UUID().uuidString.prefix(8))")
        configured = false
        poisoned = false
        attemptID = UUID()
    }

    /// If the session isn't live within 5 s, stop showing an infinite spinner:
    /// mark the attempt poisoned and surface an honest retryable state.
    private func armWatchdog() {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled, self.state == .configuring else { return }
            self.poisoned = true
            self.state = .failed("The camera didn't start — another app may be using it, or the system camera service stalled.")
        }
    }

    /// Honest states for mid-use interruptions (Camera app grabs the device,
    /// thermal shutdown, media-services reset) instead of a frozen preview.
    private func observeSession(_ s: AVCaptureSession) {
        let nc = NotificationCenter.default
        sessionObservers.append(nc.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification, object: s, queue: .main
        ) { [weak self] _ in
            self?.state = .failed("The camera was interrupted by another app or the system.")
        })
        sessionObservers.append(nc.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification, object: s, queue: .main
        ) { [weak self] _ in
            self?.start()
        })
        sessionObservers.append(nc.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: s, queue: .main
        ) { [weak self] note in
            let msg = (note.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.localizedDescription
            self?.poisoned = true
            self?.state = .failed(msg ?? "The camera hit a system error.")
        })
    }

    private func configureAndRun() {
        // Capture THIS attempt's objects. The block must never read
        // self.session/self.output: a hung block that unblocks after a retry
        // rebuilt the pair would otherwise configure/start the NEW session
        // concurrently from a stale queue (AVCaptureSession is not safe for
        // concurrent configuration). With locals, a stale attempt can only
        // touch its own abandoned objects — and rebuildSessionObjects() has
        // already queued a stopRunning behind it on the same stale queue.
        let attempt = attemptID
        let session = self.session
        let output = self.output
        let metadataOutput = self.metadataOutput
        let needsConfigure = !configured
        queue.async { [weak self] in
            if needsConfigure {
                session.beginConfiguration()
                // CRITICAL: photo-only capture must not touch the app's
                // shared AVAudioSession. The default (true) makes startRunning
                // reconfigure it — which deadlocks against SnoreDetector's
                // live .record session whenever sleep tracking is active
                // (root cause of the all-day "camera didn't start" on device:
                // the sleep session resumes on every launch, so every camera
                // start collided with it).
                session.automaticallyConfiguresApplicationAudioSession = false
                session.sessionPreset = .photo
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input),
                      session.canAddOutput(output) else {
                    session.commitConfiguration()
                    DispatchQueue.main.async { [weak self] in
                        guard let self, attempt == self.attemptID else { return }
                        self.state = .unavailable
                    }
                    return
                }
                session.addInput(input)
                session.addOutput(output)

                // Barcode / QR metadata scanning on the same session. Delegate
                // callbacks land on the main queue. metadataObjectTypes can only
                // be set AFTER the output is added to the session.
                if session.canAddOutput(metadataOutput), let self {
                    session.addOutput(metadataOutput)
                    metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
                    let wanted: [AVMetadataObject.ObjectType] =
                        [.ean13, .ean8, .upce, .code128, .qr]
                    metadataOutput.metadataObjectTypes =
                        wanted.filter { metadataOutput.availableMetadataObjectTypes.contains($0) }
                }

                session.commitConfiguration()
            }
            if !session.isRunning { session.startRunning() }
            // startRunning can also RETURN with the session not running
            // (silent failure) — don't report .ready on faith.
            let actuallyRunning = session.isRunning
            DispatchQueue.main.async { [weak self] in
                // A hung attempt may complete long after the watchdog failed
                // the UI — or after a retry already rebuilt the session pair
                // (which resets `poisoned`). The attempt token is the only
                // reliable identity check: stale attempts touch nothing.
                guard let self, attempt == self.attemptID, !self.poisoned else { return }
                self.watchdog?.cancel()
                guard actuallyRunning else {
                    self.poisoned = true
                    self.state = .failed("The camera session couldn't start. Close any app using the camera and try again.")
                    return
                }
                self.configured = true
                if self.sessionObservers.isEmpty { self.observeSession(session) }
                self.state = .ready
            }
        }
    }

    func stop() {
        watchdog?.cancel()
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capture() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            // Portrait-lock the still so meals aren't captured sideways.
            if let conn = self.output.connection(with: .video) {
                if #available(iOS 17.0, *) {
                    if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
                } else if conn.isVideoOrientationSupported {
                    conn.videoOrientation = .portrait
                }
            }
            self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }
}

extension FoodCameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        DispatchQueue.main.async { [weak self] in self?.onCapture?(image) }
    }
}

// MARK: - Barcode / QR metadata

extension FoodCameraModel: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        // Delegate already runs on the main queue. Take the first readable code.
        for object in metadataObjects {
            guard let readable = object as? AVMetadataMachineReadableCodeObject,
                  let raw = readable.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { continue }

            // QR codes may carry arbitrary payloads. Only treat a QR as a
            // product code when it encodes a bare numeric GTIN (8–14 digits);
            // ignore anything else without surfacing an error.
            if readable.type == .qr {
                let isBareGTIN = raw.allSatisfy(\.isNumber) && (8...14).contains(raw.count)
                guard isBareGTIN else { continue }
            }

            onBarcode?(raw)
            return
        }
    }
}

// MARK: - Preview layer bridge

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            guard let l = layer as? AVCaptureVideoPreviewLayer else {
                return AVCaptureVideoPreviewLayer()
            }
            return l
        }
    }
}
