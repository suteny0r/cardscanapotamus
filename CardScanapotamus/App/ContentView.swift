import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var activeSheet: ActiveSheet?
    @Query(sort: \SourceOption.createdAt) private var sourceOptions: [SourceOption]
    @Query(sort: \CategoryOption.createdAt) private var categoryOptions: [CategoryOption]
    @AppStorage("selectedCategory") private var selectedCategory: String = ""
    @Query(sort: \ScannedCard.scannedAt, order: .reverse) private var cards: [ScannedCard]
    @Environment(\.modelContext) private var modelContext
    @AppStorage("selectedSource") private var selectedSource: String = ""
    @State private var exportItem: ExportItem?
    @State private var exportError: String?
    @AppStorage("debugMode") private var debugMode: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    sourcePickerBar
                    Divider().padding(.leading, 56)
                    categoryPickerBar
                }
                .background(.bar)
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
                    CameraScannerView(defaultSource: selectedSource,
                                      defaultCategory: selectedCategory,
                                      debugMode: debugMode)
                case .manageSources:
                    ManageSourcesView()
                case .manageCategories:
                    ManageCategoriesView()
                }
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
        .onChange(of: categoryOptions) {
            if !selectedCategory.isEmpty && !categoryOptions.contains(where: { $0.name == selectedCategory }) {
                selectedCategory = ""
            }
        }
    }

    private func exportToExcel() {
        do {
            let url = try ExcelExporter.generateXLSX(from: cards, source: selectedSource)
            exportItem = ExportItem(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private var sourcePickerBar: some View {
        OptionPickerBar(
            title: "Source",
            icon: "tag.fill",
            tint: .blue,
            options: sourceOptions.map(\.name),
            selection: $selectedSource
        ) {
            activeSheet = .manageSources
        }
    }

    private var categoryPickerBar: some View {
        OptionPickerBar(
            title: "Category",
            icon: "briefcase.fill",
            tint: .green,
            options: categoryOptions.map(\.name),
            selection: $selectedCategory
        ) {
            activeSheet = .manageCategories
        }
    }
}

enum ActiveSheet: Identifiable {
    case scanner
    case manageSources
    case manageCategories

    var id: Self { self }
}
