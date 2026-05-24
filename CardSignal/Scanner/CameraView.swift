import SwiftUI
import AVFoundation

// MARK: - Camera Preview (UIKit bridge)

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Scanner Container View

struct ScannerContainerView: View {
    @StateObject private var cameraVM = CameraViewModel()
    @StateObject private var scannerVM = CardScannerViewModel()
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if cameraVM.permissionGranted {
                    CameraPreview(session: cameraVM.session)
                        .ignoresSafeArea()

                    // Card finder overlay
                    CardFinderOverlay(isDetecting: scannerVM.isDetecting)

                    VStack {
                        Spacer()
                        scannerControlsBar
                    }
                } else {
                    permissionDeniedView
                }
            }
            .navigationTitle("Scan Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                cameraVM.startSession()
                cameraVM.onFrameReady = { [weak scannerVM] buffer in
                    scannerVM?.analyzeFrame(buffer)
                }
            }
            .onDisappear { cameraVM.stopSession() }
            .sheet(item: $scannerVM.identificationResult) { result in
                CardMatchResultSheet(result: result, onSave: { card in
                    scannerVM.saveCard(card)
                })
                .environmentObject(subscriptionManager)
            }
            .alert("Error", isPresented: .constant(cameraVM.error != nil)) {
                Button("OK") { cameraVM.error = nil }
            } message: {
                Text(cameraVM.error ?? "")
            }
        }
    }

    private var scannerControlsBar: some View {
        HStack(spacing: 32) {
            Spacer()
            // Capture button
            Button {
                cameraVM.capturePhoto()
                if let img = cameraVM.capturedImage {
                    Task { await scannerVM.identify(image: img) }
                }
            } label: {
                ZStack {
                    Circle().fill(.white).frame(width: 72, height: 72)
                    Circle().stroke(.white.opacity(0.4), lineWidth: 4).frame(width: 84, height: 84)
                    if scannerVM.isProcessing {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "camera.fill").font(.title2).foregroundStyle(.black)
                    }
                }
            }
            .disabled(scannerVM.isProcessing)
            Spacer()
        }
        .padding(.bottom, 40)
    }

    private var permissionDeniedView: some View {
        ContentUnavailableView {
            Label("Camera Access Required", systemImage: "camera.fill")
        } description: {
            Text("CardSignal needs camera access to scan cards.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Card Finder Overlay

struct CardFinderOverlay: View {
    var isDetecting: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width * 0.85
            let h = w * 1.4  // standard card aspect ~2.5 x 3.5 inches
            let x = (geo.size.width - w) / 2
            let y = (geo.size.height - h) / 2.5

            ZStack {
                // Dimmed outside
                Color.black.opacity(0.45)
                    .mask(
                        Rectangle()
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .frame(width: w, height: h)
                                    .offset(x: x - geo.size.width / 2 + w / 2,
                                            y: y - geo.size.height / 2 + h / 2)
                                    .blendMode(.destinationOut)
                            )
                    )

                // Corner brackets
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isDetecting ? .green : .white, lineWidth: 2)
                    .frame(width: w, height: h)
                    .offset(x: x - geo.size.width / 2 + w / 2,
                            y: y - geo.size.height / 2 + h / 2)
                    .animation(.easeInOut(duration: 0.3), value: isDetecting)

                VStack {
                    Spacer()
                    Text(isDetecting ? "Card detected" : "Align card in frame")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(.bottom, geo.size.height * 0.35)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Match Result Sheet

struct CardMatchResultSheet: View {
    let result: IdentificationResult
    let onSave: (CardMatch) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMatch: CardMatch?
    @State private var navigateToDetail = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(result.matches) { match in
                        CardMatchRow(match: match) {
                            selectedMatch = match
                            navigateToDetail = true
                        } onSave: {
                            onSave(match)
                            dismiss()
                        }
                    }
                } header: {
                    Text("\(result.matches.count) match\(result.matches.count == 1 ? "" : "es") found • \(result.processingTimeMs)ms")
                        .font(.caption)
                }
            }
            .navigationTitle("Scan Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $navigateToDetail) {
                if let match = selectedMatch {
                    CardDetailView(card: match)
                }
            }
        }
    }
}

struct CardMatchRow: View {
    let match: CardMatch
    let onDetail: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: match.imageURL)) { img in
                img.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.2))
            }
            .frame(width: 50, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 4) {
                Text(match.name).font(.headline)
                Text("\(match.setName) · #\(match.collectorNumber)")
                    .font(.caption).foregroundStyle(.secondary)
                Text(match.rarity).font(.caption2).foregroundStyle(.tertiary)
                HStack {
                    Text(match.price.formattedMarket)
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(.green)
                    Text(match.price.formattedRange)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(spacing: 8) {
                ConfidenceBadge(percent: match.confidencePercent)
                Button(action: onSave) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.red)
                }
                Button(action: onDetail) {
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

struct ConfidenceBadge: View {
    let percent: Int
    var color: Color { percent >= 80 ? .green : percent >= 60 ? .orange : .red }

    var body: some View {
        Text("\(percent)%")
            .font(.caption2).fontWeight(.bold)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}
