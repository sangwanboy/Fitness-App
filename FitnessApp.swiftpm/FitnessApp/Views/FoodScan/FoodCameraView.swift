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

    @StateObject private var cam = FoodCameraModel()
    @State private var photoItem: PhotosPickerItem? = nil

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
            }

            // Overlay chrome
            VStack(spacing: 0) {
                topBar
                Spacer()
                if cam.state == .ready {
                    Text("Center your meal in the frame")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.35), in: Capsule())
                        .padding(.bottom, 16)
                }
                bottomControls
            }
        }
        .onAppear {
            cam.onCapture = { img in onImage(img) }
            cam.start()
        }
        .onDisappear { cam.stop() }
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
                            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.5), lineWidth: 1))
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

    private func stateMessage(icon: String, title: String, body: String, showSettings: Bool) -> some View {
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
    enum CamState { case configuring, ready, denied, unavailable }

    @Published var state: CamState = .configuring

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "fitnessapp.food.camera")
    private var configured = false

    /// Called on the main thread with the captured/normalised still.
    var onCapture: ((UIImage) -> Void)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.configureAndRun() }
                    else { self?.state = .denied }
                }
            }
        default:
            state = .denied
        }
    }

    private func configureAndRun() {
        queue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input),
                      self.session.canAddOutput(self.output) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.state = .unavailable }
                    return
                }
                self.session.addInput(input)
                self.session.addOutput(self.output)
                self.session.commitConfiguration()
                self.configured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.state = .ready }
        }
    }

    func stop() {
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
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
