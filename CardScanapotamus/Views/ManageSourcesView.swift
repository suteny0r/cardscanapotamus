import SwiftUI
import SwiftData

struct ManageSourcesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SourceOption.createdAt) private var sourceOptions: [SourceOption]
    @State private var newSourceName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New source name", text: $newSourceName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                        Button {
                            addSource()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                        .disabled(newSourceName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section {
                    if sourceOptions.isEmpty {
                        Text("No sources yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sourceOptions) { option in
                            Text(option.name)
                        }
                        .onDelete(perform: deleteSources)
                    }
                }
            }
            .navigationTitle("Manage Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func addSource() {
        let trimmed = newSourceName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let option = SourceOption(name: trimmed)
        modelContext.insert(option)
        newSourceName = ""
    }

    private func deleteSources(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sourceOptions[index])
        }
    }
}
