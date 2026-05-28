import AVFoundation
import UIKit
import Combine
import AudioToolbox

@MainActor
final class CameraViewModel: NSObject, ObservableObject {
    @Published var capturedImage: UIImage?
    @Published var isCapturing = false
    @Published var error: String?
    @Published var permissionGranted = false

    // nonisolated(unsafe): AVCaptureSession is thread-safe for start/stop;
    // we never mutate the reference itself after init.
    nonisolated(unsafe) let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var videoOutput: AVCaptureVideoDataOutput?
    private var cameraDevice: AVCaptureDevice?

    // Stored nonisolated so the video-queue delegate can call it without
    // crossing actor boundaries. The closure itself must be concurrency-safe.
    nonisolated(unsafe) var onFrameReady: ((CVPixelBuffer) -> Void)?

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
        cameraDevice = device
        configureCameraDevice(device)

        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.maxPhotoQualityPrioritization = .quality
        }

        // Video data output for live card detection
        let videoOut = AVCaptureVideoDataOutput()
        videoOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOut.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.appgumbo.rarecheck.videoQueue"))
        videoOut.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOut) {
            session.addOutput(videoOut)
            videoOutput = videoOut
        }

        session.commitConfiguration()
        alignVideoConnectionsForPortrait()
    }

    func startSession() {
        // Capture session ref locally — safe because session is nonisolated(unsafe)
        let captureSession = session
        Task.detached(priority: .userInitiated) {
            captureSession.startRunning()
        }
    }

    func stopSession() {
        let captureSession = session
        Task.detached(priority: .background) {
            captureSession.stopRunning()
        }
    }

    // MARK: - Capture

    func capturePhoto() {
        guard !isCapturing else { return }
        isCapturing = true
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        settings.isHighResolutionPhotoEnabled = true
        settings.photoQualityPrioritization = .quality
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func configureCameraDevice(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            device.unlockForConfiguration()
        } catch {
            self.error = "Could not optimize camera focus."
        }
    }

    private func alignVideoConnectionsForPortrait() {
        [photoOutput.connection(with: .video), videoOutput?.connection(with: .video)]
            .compactMap { $0 }
            .forEach { connection in
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
    }

    private func playCaptureFeedback() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlaySystemSound(1108)
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
            self.playCaptureFeedback()
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
