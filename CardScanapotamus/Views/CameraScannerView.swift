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
    @State private var showImagePicker = false

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
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(sourceType: .camera) { image in
                    if let image {
                        processImage(image)
                    }
                }
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
                showImagePicker = true
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

// MARK: - UIImagePickerController Wrapper

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImagePicked: (UIImage?) -> Void

        init(onImagePicked: @escaping (UIImage?) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            picker.dismiss(animated: true)
            onImagePicked(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            onImagePicked(nil)
        }
    }
}
