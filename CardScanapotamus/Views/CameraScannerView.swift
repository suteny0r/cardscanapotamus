import SwiftUI
import AVFoundation

struct CameraScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var capturedImage: UIImage?
    @State private var isProcessing = false
    @State private var scannedCard: ScannedCard?
    @State private var errorMessage: String?
    @State private var showImagePicker = false
    @State private var imageSource: UIImagePickerController.SourceType = .camera

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let card = scannedCard {
                    CardDetailView(card: card, isNewScan: true) {
                        modelContext.insert(card)
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
                ImagePicker(sourceType: imageSource) { image in
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

            Text("Take a photo or choose from your library")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                Button {
                    imageSource = .camera
                    showImagePicker = true
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    imageSource = .photoLibrary
                    showImagePicker = true
                } label: {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
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
                let lines = try await OCRService.recognizeText(in: image)
                var card = ContactParser.parse(lines: lines)
                card.imageData = image.jpegData(compressionQuality: 0.7)
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
