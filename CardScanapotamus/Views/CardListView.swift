import SwiftUI
import SwiftData

struct CardListView: View {
    @Query(sort: \ScannedCard.scannedAt, order: .reverse) private var cards: [ScannedCard]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if cards.isEmpty {
                ContentUnavailableView {
                    Label("No Cards Scanned", systemImage: "creditcard")
                } description: {
                    Text("Tap the camera button to scan your first business card.")
                }
            } else {
                List {
                    ForEach(cards) { card in
                        NavigationLink {
                            CardDetailView(card: card)
                        } label: {
                            cardRow(card)
                        }
                    }
                    .onDelete(perform: deleteCards)
                }
            }
        }
    }

    private func cardRow(_ card: ScannedCard) -> some View {
        HStack(spacing: 12) {
            if let imageData = card.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: 56, height: 36)
                    .overlay {
                        Image(systemName: "creditcard")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(card.fullName.isEmpty ? "Unknown" : card.fullName)
                    .font(.headline)
                if !card.company.isEmpty {
                    Text(card.company)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !card.jobTitle.isEmpty {
                    Text(card.jobTitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let source = card.source, !source.isEmpty {
                    Text(source)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.7))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func deleteCards(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(cards[index])
        }
    }
}

struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
