import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var activeSheet: ActiveSheet?
    @Query(sort: \SourceOption.createdAt) private var sourceOptions: [SourceOption]
    @Query(sort: \ScannedCard.scannedAt, order: .reverse) private var cards: [ScannedCard]
    @Environment(\.modelContext) private var modelContext
    @AppStorage("selectedSource") private var selectedSource: String = ""
    @State private var showDeleteAllConfirm = false
    @State private var exportItem: ExportItem?
    @State private var exportError: String?
    @AppStorage("debugMode") private var debugMode: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sourcePickerBar
                CardListView()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 8) {
                        Image("AppIconImage")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .overlay(
                                debugMode ? RoundedRectangle(cornerRadius: 7)
                                    .stroke(.red, lineWidth: 2) : nil
                            )
                            .onLongPressGesture {
                                debugMode.toggle()
                            }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        if !cards.isEmpty {
                            Button {
                                exportToExcel()
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                            Button(role: .destructive) {
                                showDeleteAllConfirm = true
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        Button {
                            activeSheet = .scanner
                        } label: {
                            Image(systemName: "camera.fill")
                                .font(.title2)
                        }
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .scanner:
                    CameraScannerView(defaultSource: selectedSource, debugMode: debugMode)
                case .manageSources:
                    ManageSourcesView()
                }
            }
            .confirmationDialog("Delete All Cards", isPresented: $showDeleteAllConfirm, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) {
                    for card in cards {
                        modelContext.delete(card)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all \(cards.count) scanned cards.")
            }
            .sheet(item: $exportItem) { item in
                ShareSheet(items: [item.url])
            }
            .alert("Export Error", isPresented: .init(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK") { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
        }
        .onChange(of: sourceOptions) {
            if !selectedSource.isEmpty && !sourceOptions.contains(where: { $0.name == selectedSource }) {
                selectedSource = ""
            }
        }
    }

    private func exportToExcel() {
        do {
            let url = try ExcelExporter.generateXLSX(from: cards)
            exportItem = ExportItem(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private var sourcePickerBar: some View {
        HStack {
            Image(systemName: "tag.fill")
                .foregroundStyle(.blue)
                .frame(width: 24)

            Text("Source:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if sourceOptions.isEmpty {
                Text("None defined")
                    .foregroundStyle(.tertiary)
                    .font(.subheadline)
            } else {
                Picker("Source", selection: $selectedSource) {
                    Text("None").tag("")
                    ForEach(sourceOptions) { option in
                        Text(option.name).tag(option.name)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            Spacer()

            Button {
                activeSheet = .manageSources
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.title3)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

enum ActiveSheet: Identifiable {
    case scanner
    case manageSources

    var id: Self { self }
}
