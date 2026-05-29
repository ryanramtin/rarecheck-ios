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
    @EnvironmentObject var appNavigation: AppNavigationState
    @State private var capturedPreview: UIImage?
    @State private var resultCapture: UIImage?
    @State private var pendingLockedCapture = false
    @State private var isAutoCapturePending = false
    @State private var capturePulse = false
    @State private var showPaywall = false
    @State private var autoCaptureTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if cameraVM.permissionGranted {
                    CameraPreview(session: cameraVM.session)
                        .ignoresSafeArea()

                    // Card finder overlay
                    CardFinderOverlay(
                        isDetecting: scannerVM.isDetecting,
                        isFramed: scannerVM.isFramed,
                        captureReadiness: scannerVM.captureReadiness,
                        isLocked: scannerVM.isLocked,
                        lockProgress: scannerVM.lockProgress,
                        isCapturing: cameraVM.isCapturing,
                        isAutoCapturePending: isAutoCapturePending,
                        isCaptured: capturedPreview != nil,
                        isSearching: scannerVM.isProcessing,
                        capturePulse: capturePulse,
                        capturedImage: capturedPreview
                    )
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
                    Task { @MainActor in
                        scannerVM?.analyzeFrame(buffer)
                    }
                }
            }
            .onDisappear {
                autoCaptureTask?.cancel()
                autoCaptureTask = nil
                isAutoCapturePending = false
                pendingLockedCapture = false
                cameraVM.onFrameReady = nil
                cameraVM.stopSession()
            }
            // Photo capture is async — kick off identification once the
            // image actually lands in @Published capturedImage, then clear
            // it so the next auto-capture fires a fresh identify().
            .onChange(of: cameraVM.capturedImage) { _, newImage in
                guard let img = newImage else { return }
                guard pendingLockedCapture else {
                    cameraVM.capturedImage = nil
                    scannerVM.lastError = "Card is not locked yet. Fill the frame with one card and wait for the green auto-capture border."
                    return
                }
                pendingLockedCapture = false
                Task {
                    let preparedImage = await scannerVM.prepareCapturedImage(img)
                    await MainActor.run {
                        resultCapture = preparedImage
                        withAnimation(.easeOut(duration: 0.12)) {
                            capturedPreview = preparedImage
                            capturePulse = true
                        }
                    }
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    await MainActor.run {
                        withAnimation(.easeOut(duration: 0.2)) { capturePulse = false }
                    }
                    await scannerVM.identifyPreparedCard(image: preparedImage)
                    await MainActor.run {
                        scannerVM.markCaptureFinished()
                        withAnimation(.easeOut(duration: 0.2)) {
                            capturedPreview = nil
                            cameraVM.capturedImage = nil
                        }
                    }
                }
            }
            .onChange(of: scannerVM.shouldAutoCapture) { _, shouldCapture in
                guard shouldCapture,
                      !pendingLockedCapture,
                      !isAutoCapturePending,
                      !cameraVM.isCapturing,
                      !scannerVM.isProcessing,
                      capturedPreview == nil else {
                    return
                }
                isAutoCapturePending = true
                autoCaptureTask?.cancel()
                autoCaptureTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    defer { isAutoCapturePending = false }
                    guard !Task.isCancelled else { return }
                    guard scannerVM.shouldAutoCapture,
                          scannerVM.isLocked,
                          cameraVM.isSessionRunning,
                          !cameraVM.isCapturing,
                          !scannerVM.isProcessing,
                          capturedPreview == nil else {
                        return
                    }
                    triggerCapture()
                }
            }
            // Surface local identification guidance so "thinking → nothing"
            // is not silent when OCR cannot confirm a card.
            .alert("Scan failed", isPresented: .constant(scannerVM.lastError != nil)) {
                Button("OK") { scannerVM.clearErrorAndResumeScanning() }
            } message: {
                Text(scannerVM.lastError ?? "")
            }
            .sheet(item: $scannerVM.identificationResult) { result in
                CardMatchResultSheet(result: result, capturedImage: resultCapture, onSave: { card in
                    let outcome = scannerVM.saveCard(card, isPro: subscriptionManager.isPro)
                    if outcome == .limitReached {
                        showPaywall = true
                    } else {
                        appNavigation.showCollection(for: card.name, outcome: outcome)
                    }
                })
                .environmentObject(subscriptionManager)
                .onDisappear {
                    scannerVM.identificationResult = nil
                    resultCapture = nil
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .environmentObject(subscriptionManager)
            }
            .alert("Error", isPresented: .constant(cameraVM.error != nil)) {
                Button("OK") { cameraVM.error = nil }
            } message: {
                Text(cameraVM.error ?? "")
            }
        }
    }

    private var permissionDeniedView: some View {
        ContentUnavailableView {
            Label("Camera Access Required", systemImage: "camera.fill")
        } description: {
            Text("Poke Rare Check needs camera access to scan cards.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private func triggerCapture() {
        guard scannerVM.isLocked else {
            scannerVM.lastError = "Card is not locked yet. Fill the frame with one card and wait for the green auto-capture border."
            return
        }
        pendingLockedCapture = true
        scannerVM.markCaptureStarted()
        cameraVM.capturePhoto()
        if !cameraVM.isCapturing {
            pendingLockedCapture = false
            scannerVM.markCaptureFinished()
        }
    }
}

// MARK: - Card Finder Overlay

struct CardFinderOverlay: View {
    var isDetecting: Bool
    var isFramed: Bool
    var captureReadiness: CaptureReadiness
    var isLocked: Bool
    var lockProgress: Double
    var isCapturing: Bool
    var isAutoCapturePending: Bool
    var isCaptured: Bool
    var isSearching: Bool
    var capturePulse: Bool
    var capturedImage: UIImage?
    @State private var searchStartDate = Date()

    private var borderColor: Color {
        if isSearching { return .cyan }
        if isCaptured { return .yellow }
        if isCapturing || isAutoCapturePending { return .orange }
        if isLocked { return .green }
        if isFramed && captureReadiness != .ready { return .orange }
        if isDetecting { return .mint }
        return .white
    }

    private var statusText: String {
        if isSearching { return "Searching Pokemon database..." }
        if isCaptured { return "Captured - searching" }
        if isCapturing { return "Hold still - capturing" }
        if isAutoCapturePending { return "Capturing automatically" }
        if isLocked { return "Locked - auto capture" }
        if isFramed { return captureReadiness.guidanceText }
        if isDetecting { return "Center card in frame" }
        return "Align card in frame"
    }

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
                if let capturedImage {
                    Image(uiImage: capturedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: h)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.black.opacity(isSearching ? 0.08 : 0))
                        )
                        .offset(x: x - geo.size.width / 2 + w / 2,
                                y: y - geo.size.height / 2 + h / 2)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: isLocked || isCaptured || isSearching || isCapturing || isAutoCapturePending ? 5 : 2)
                    .frame(width: w, height: h)
                    .offset(x: x - geo.size.width / 2 + w / 2,
                            y: y - geo.size.height / 2 + h / 2)
                    .shadow(color: borderColor.opacity(isLocked || isCaptured || isSearching || isCapturing || isAutoCapturePending ? 0.95 : 0.35), radius: capturePulse || isAutoCapturePending ? 24 : 8)
                    .scaleEffect(capturePulse || isAutoCapturePending ? 1.025 : 1)
                    .animation(.easeInOut(duration: 0.22), value: isDetecting)
                    .animation(.easeInOut(duration: 0.16), value: isLocked)
                    .animation(.easeInOut(duration: 0.12), value: isAutoCapturePending)
                    .animation(.spring(response: 0.22, dampingFraction: 0.7), value: capturePulse)

                if isDetecting && !isLocked {
                    VStack(spacing: 8) {
                        ProgressView(value: min(max(lockProgress, 0), 1))
                            .progressViewStyle(.linear)
                            .tint(captureReadiness == .ready ? .green : .mint)
                            .frame(width: w * 0.72)
                        Text(captureReadiness.guidanceText)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(statusBackground, in: Capsule())
                    }
                    .offset(y: y - geo.size.height / 2 + h + 25)
                }

                if isSearching {
                    HStack(spacing: 6) {
                        RotatingPokeballView()
                        Text("Pokemon DB")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .offset(x: x - geo.size.width / 2 + w * 0.25,
                            y: y - geo.size.height / 2 - 18)
                }

                if isAutoCapturePending || isCapturing || isCaptured {
                    VStack(spacing: 8) {
                        if isCaptured {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 44, weight: .bold))
                        } else {
                            ProgressView()
                                .tint(.white)
                                .controlSize(.large)
                        }
                        Text(isCaptured ? "Captured" : "Capturing")
                            .font(.headline.weight(.bold))
                        if !isCaptured {
                            Text("Automatically")
                                .font(.caption.weight(.semibold))
                                .textCase(.uppercase)
                                .foregroundStyle(.white.opacity(0.78))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .background(statusBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.24), lineWidth: 1)
                    )
                    .shadow(color: statusBackground.opacity(0.65), radius: 22)
                    .offset(x: x - geo.size.width / 2 + w / 2,
                            y: y - geo.size.height / 2 + h / 2)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }

                VStack {
                    Spacer()
                    statusPill
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(statusBackground, in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                        .padding(.bottom, max(90, geo.size.height * 0.30))
                }
            }
        }
        .onChange(of: isSearching) { _, searching in
            if searching { searchStartDate = Date() }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var statusPill: some View {
        if isSearching {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                HStack(spacing: 8) {
                    RotatingPokeballView()
                    Text("Searching Pokemon DB \(max(0, Int(context.date.timeIntervalSince(searchStartDate))))s")
                }
            }
        } else {
            HStack(spacing: 8) {
                if isCaptured {
                    Image(systemName: "checkmark.circle.fill")
                } else if isCapturing || isAutoCapturePending {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                } else if isLocked {
                    Image(systemName: "checkmark.seal.fill")
                } else if isFramed {
                    Image(systemName: "viewfinder.circle.fill")
                } else if isDetecting {
                    Image(systemName: "viewfinder")
                }
                Text(statusText)
            }
        }
    }

    private var statusBackground: Color {
        if isSearching { return .cyan.opacity(0.78) }
        if isCaptured { return .yellow.opacity(0.78) }
        if isCapturing || isAutoCapturePending { return .orange.opacity(0.82) }
        if isLocked { return .green.opacity(0.78) }
        if isFramed && captureReadiness != .ready { return .orange.opacity(0.72) }
        if isFramed { return .mint.opacity(0.72) }
        return .black.opacity(0.58)
    }

}

struct RotatingPokeballView: View {
    @State private var rotation = 0.0

    var body: some View {
        Image("Pokeball")
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .clipShape(Circle())
            .rotationEffect(.degrees(rotation))
            .onAppear { rotation = 360 }
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: rotation)
    }
}

// MARK: - Match Result Sheet

struct CardMatchResultSheet: View {
    let result: IdentificationResult
    let capturedImage: UIImage?
    let onSave: (CardMatch) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMatch: CardMatch?
    @State private var navigateToDetail = false

    var body: some View {
        NavigationStack {
            List {
                if let first = result.matches.first {
                    Section {
                        MatchRevealView(capturedImage: capturedImage, match: first)
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    }
                }

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
                    Button("Done") {
                        if let first = result.matches.first {
                            onSave(first)
                        }
                        dismiss()
                    }
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

struct MatchRevealView: View {
    let capturedImage: UIImage?
    let match: CardMatch
    @State private var revealDatabaseCard = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.black.opacity(0.04))

                if let capturedImage {
                    Image(uiImage: capturedImage)
                        .resizable()
                        .scaledToFit()
                        .padding(14)
                        .opacity(revealDatabaseCard ? 0 : 1)
                        .scaleEffect(revealDatabaseCard ? 0.88 : 1)
                        .blur(radius: revealDatabaseCard ? 3 : 0)
                }

                AsyncImage(url: match.preferredDisplayImageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(14)
                            .opacity(revealDatabaseCard ? 1 : 0)
                            .scaleEffect(revealDatabaseCard ? 1 : 0.82)
                    case .failure:
                        Image(systemName: "rectangle.stack.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.secondary)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }

                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("Matched in Pokemon database")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .background(.green.opacity(0.92), in: Capsule())
                    .opacity(revealDatabaseCard ? 1 : 0)
                    .offset(y: revealDatabaseCard ? 0 : 12)
                    .padding(.bottom, 12)
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Text(match.name)
                .font(.headline)
            Text("\(match.setName) · #\(match.collectorNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            revealDatabaseCard = false
            withAnimation(.spring(response: 0.48, dampingFraction: 0.82).delay(0.35)) {
                revealDatabaseCard = true
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
            AsyncImage(url: match.preferredDisplayImageURL) { img in
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
