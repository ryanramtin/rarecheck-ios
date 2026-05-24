import AVFoundation
import UIKit
import Combine

@MainActor
final class CameraViewModel: NSObject, ObservableObject {
    @Published var capturedImage: UIImage?
    @Published var isCapturing = false
    @Published var error: String?
    @Published var permissionGranted = false

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var videoOutput: AVCaptureVideoDataOutput?

    // Callback for when a frame is ready for analysis
    var onFrameReady: ((CVPixelBuffer) -> Void)?

    override init() {
        super.init()
        Task { await checkPermission() }
    }

    // MARK: - Permission

    func checkPermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            await setupSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permissionGranted = granted
            if granted { await setupSession() }
        default:
            permissionGranted = false
            error = "Camera access denied. Please enable in Settings."
        }
    }

    // MARK: - Session Setup

    func setupSession() async {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            error = "Could not access camera."
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
        }

        // Video data output for live card detection
        let videoOut = AVCaptureVideoDataOutput()
        videoOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOut.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.cardsignal.videoQueue"))
        videoOut.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOut) {
            session.addOutput(videoOut)
            videoOutput = videoOut
        }

        session.commitConfiguration()
    }

    func startSession() {
        Task.detached(priority: .userInitiated) { [weak self] in
            self?.session.startRunning()
        }
    }

    func stopSession() {
        Task.detached(priority: .background) { [weak self] in
            self?.session.stopRunning()
        }
    }

    // MARK: - Capture

    func capturePhoto() {
        guard !isCapturing else { return }
        isCapturing = true
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraViewModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            self.isCapturing = false
            if let error {
                self.error = error.localizedDescription
                return
            }
            guard let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) else {
                self.error = "Failed to process photo."
                return
            }
            self.capturedImage = image
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrameReady?(pixelBuffer)
    }
}
