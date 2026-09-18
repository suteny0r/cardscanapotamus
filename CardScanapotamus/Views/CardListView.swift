import SwiftUI
import SwiftData

struct CardListView: View {
    @Query(sort: \ScannedCard.scannedAt, order: .reverse) private var cards: [ScannedCard]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""

    private var filteredCards: [ScannedCard] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return cards }
        let terms = query.split(separator: " ").map(String.init)
        return cards.filter { card in
            let haystack = searchableText(for: card)
            return terms.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
        }
    }

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
                    ForEach(filteredCards) { card in
                        NavigationLink {
                            CardDetailView(card: card)
                        } label: {
                            cardRow(card)
                        }
                    }
                    .onDelete(perform: deleteCards)
                }
                .overlay {
                    if filteredCards.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
                .searchable(text: $searchText, prompt: "Search cards")
                .autocorrectionDisabled()
            }
        }
    }

    /// Every field a user might reasonably search on, joined for matching.
    private func searchableText(for card: ScannedCard) -> String {
        var parts: [String] = [
            card.fullName, card.jobTitle, card.company, card.email,
            card.phone, card.website, card.address, card.rawText
        ]
        let optionals: [String?] = [
            card.phone2, card.phone3,
            card.addressLine1, card.addressLine2,
            card.city, card.state, card.zip, card.country,
            card.source, card.category, card.notes, card.backRawText
        ]
        parts.append(contentsOf: optionals.compactMap { $0 })
        return parts.joined(separator: "\n")
    }

    private func cardRow(_ card: ScannedCard) -> some View {
        HStack(spacing: 12) {
            if let uiImage = CardImage.decode(card.imageData, maxPixel: 240) {
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
                HStack(spacing: 6) {
                    if let source = card.source, !source.isEmpty {
                        TagBadge(text: source, tint: .blue)
                    }
                    if let category = card.category, !category.isEmpty {
                        TagBadge(text: category, tint: .green)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func deleteCards(at offsets: IndexSet) {
        let visible = filteredCards
        for index in offsets {
            modelContext.delete(visible[index])
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

struct TagBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.7))
            .clipShape(Capsule())
    }
}
