import SwiftUI
import AVFoundation

struct CameraScannerView: View {
    var defaultSource: String = ""

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var capturedImage: UIImage?
    @State private var isProcessing = false
    @State private var scannedCard: ScannedCard?
    @State private var errorMessage: String?
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let card = scannedCard {
                    CardDetailView(card: card, isNewScan: true) {
                        modelContext.insert(card)
                        try? modelContext.save()
                        dismiss()
                    }
                } else if isProcessing {
                    Spacer()
                    ProgressView("Scanning card...")
                        .font(.headline)
                    Spacer()
                } else {
                    scanPromptView
                }
            }
            .navigationTitle("Scan Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView { image in
                    if let image {
                        processImage(image)
                    }
                }
                .ignoresSafeArea()
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var scanPromptView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "creditcard.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text("Scan a Business Card")
                .font(.title2.bold())

            Text("Take a photo of a business card")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                showCamera = true
            } label: {
                Label("Take Photo", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    private func processImage(_ image: UIImage) {
        capturedImage = image
        isProcessing = true

        Task {
            do {
                var card: ScannedCard

                // Check for QR code with vCard first — if found, use it as sole source
                let payloads = (try? await OCRService.detectBarcodes(in: image)) ?? []
                let vcard = payloads.first(where: { VCardParser.isVCard($0) })

                if let vcard {
                    card = ScannedCard()
                    VCardParser.apply(vcard: vcard, to: &card)
                } else {
                    // No vCard — fall back to OCR
                    let lines = try await OCRService.recognizeText(in: image)
                    card = ContactParser.parse(lines: lines)
                }

                card.imageData = image.jpegData(compressionQuality: 0.7)
                card.source = defaultSource.isEmpty ? nil : defaultSource
                scannedCard = card
            } catch {
                errorMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }
}

// MARK: - Custom Camera with AVCaptureSession

struct CameraView: UIViewControllerRepresentable {
    let onImagePicked: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onImagePicked = onImagePicked
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onImagePicked: ((UIImage?) -> Void)?

    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func setupCamera() {
        captureSession.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        // Set 2x zoom
        try? device.lockForConfiguration()
        device.videoZoomFactor = min(2.0, device.activeFormat.videoMaxZoomFactor)
        device.unlockForConfiguration()

        // Preview layer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }

    private func setupUI() {
        // Cancel button
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 18)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        // Capture button — white circle
        let captureButton = UIButton(type: .custom)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.layer.cornerRadius = 35
        captureButton.layer.borderWidth = 4
        captureButton.layer.borderColor = UIColor.white.cgColor
        captureButton.backgroundColor = UIColor.white.withAlphaComponent(0.9)
        captureButton.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        view.addSubview(captureButton)

        NSLayoutConstraint.activate([
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            captureButton.widthAnchor.constraint(equalToConstant: 70),
            captureButton.heightAnchor.constraint(equalToConstant: 70),
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])
    }

    @objc private func cancelTapped() {
        captureSession.stopRunning()
        onImagePicked?(nil)
        dismiss(animated: true)
    }

    @objc private func captureTapped() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        captureSession.stopRunning()
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            onImagePicked?(nil)
            dismiss(animated: true)
            return
        }
        onImagePicked?(image)
        dismiss(animated: true)
    }
}
