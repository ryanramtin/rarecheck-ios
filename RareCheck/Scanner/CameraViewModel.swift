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
    @Published var isPermissionResolved = false
    @Published private(set) var isSessionConfigured = false
    @Published private(set) var isSessionRunning = false
    @Published private(set) var isSessionStarting = false

    // nonisolated(unsafe): AVCaptureSession is thread-safe for start/stop;
    // we never mutate the reference itself after init.
    nonisolated(unsafe) let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var videoOutput: AVCaptureVideoDataOutput?
    private var cameraDevice: AVCaptureDevice?
    private var configuredMaxPhotoDimensions: CMVideoDimensions?
    private var shouldStartAfterConfiguration = false
    private var sessionStartGeneration = 0

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
            isPermissionResolved = true
            await setupSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permissionGranted = granted
            isPermissionResolved = true
            if granted { await setupSession() }
        default:
            permissionGranted = false
            isPermissionResolved = true
            error = "Camera access denied. Please enable in Settings."
        }
    }

    // MARK: - Session Setup

    func setupSession() async {
        guard !isSessionConfigured else { return }
        if session.isRunning {
            isSessionRunning = true
        }
        session.beginConfiguration()
        session.sessionPreset = .high

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
            if let dimensions = preferredPhotoDimensions(for: device) {
                photoOutput.maxPhotoDimensions = dimensions
                configuredMaxPhotoDimensions = dimensions
            }
            photoOutput.maxPhotoQualityPrioritization = .balanced
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
        isSessionConfigured = true
        if shouldStartAfterConfiguration {
            shouldStartAfterConfiguration = false
            startSession()
        }
    }

    func startSession() {
        guard permissionGranted else {
            shouldStartAfterConfiguration = true
            return
        }
        guard isSessionConfigured else {
            shouldStartAfterConfiguration = true
            return
        }
        guard !isSessionRunning, !isSessionStarting else { return }
        isSessionStarting = true
        sessionStartGeneration += 1
        let generation = sessionStartGeneration
        // Capture session ref locally — safe because session is nonisolated(unsafe)
        let captureSession = session
        Task.detached(priority: .userInitiated) {
            captureSession.startRunning()
            await MainActor.run {
                guard self.sessionStartGeneration == generation else {
                    if captureSession.isRunning {
                        Task.detached(priority: .background) {
                            captureSession.stopRunning()
                        }
                    }
                    return
                }
                self.isSessionStarting = false
                self.isSessionRunning = captureSession.isRunning
            }
        }
    }

    func stopSession() {
        shouldStartAfterConfiguration = false
        sessionStartGeneration += 1
        isSessionStarting = false
        guard isSessionRunning || session.isRunning else { return }
        isSessionRunning = false
        let captureSession = session
        Task.detached(priority: .background) {
            captureSession.stopRunning()
        }
    }

    // MARK: - Capture

    func capturePhoto() {
        guard permissionGranted,
              isSessionConfigured,
              isSessionRunning,
              !isCapturing else { return }
        guard photoOutput.connection(with: .video) != nil else {
            error = "Camera is still getting ready. Try again in a moment."
            return
        }
        isCapturing = true
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        if let configuredMaxPhotoDimensions {
            settings.maxPhotoDimensions = configuredMaxPhotoDimensions
        }
        settings.photoQualityPrioritization = .balanced
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
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            }
    }

    private func preferredPhotoDimensions(for device: AVCaptureDevice) -> CMVideoDimensions? {
        device.activeFormat.supportedMaxPhotoDimensions.max { lhs, rhs in
            Int64(lhs.width) * Int64(lhs.height) < Int64(rhs.width) * Int64(rhs.height)
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
