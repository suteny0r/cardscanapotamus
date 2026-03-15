import SwiftUI
import SwiftData

struct CardDetailView: View {
    @Bindable var card: ScannedCard
    var isNewScan: Bool = false
    var onSave: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SourceOption.createdAt) private var sourceOptions: [SourceOption]
    @State private var isSavingToContacts = false
    @State private var contactsSaved = false
    @State private var alertMessage: String?
    @State private var showDeleteConfirm = false
    @State private var showSettingsAlert = false

    var body: some View {
        List {
            if let imageData = card.imageData, let uiImage = UIImage(data: imageData) {
                Section {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: .infinity)
                }
            }

            Section("Contact Info") {
                EditableRow(label: "Name", text: $card.fullName, icon: "person.fill")
                EditableRow(label: "Title", text: $card.jobTitle, icon: "briefcase.fill")
                EditableRow(label: "Company", text: $card.company, icon: "building.2.fill")
            }

            Section("Contact Details") {
                EditableRow(label: "Email", text: $card.email, icon: "envelope.fill")
                EditableRow(label: "Phone", text: $card.phone, icon: "phone.fill")
                EditableRow(label: "Website", text: $card.website, icon: "globe")
                EditableRow(label: "Address", text: $card.address, icon: "mappin.circle.fill")
            }

            Section("Source & Notes") {
                HStack {
                    Image(systemName: "tag.fill")
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    if sourceOptions.isEmpty {
                        TextField("Source", text: Binding(
                            get: { card.source ?? "" },
                            set: { card.source = $0.isEmpty ? nil : $0 }
                        ))
                    } else {
                        Picker("Source", selection: Binding(
                            get: { card.source ?? "" },
                            set: { card.source = $0.isEmpty ? nil : $0 }
                        )) {
                            Text("None").tag("")
                            ForEach(sourceOptions) { option in
                                Text(option.name).tag(option.name)
                            }
                        }
                        .labelsHidden()
                    }
                }
                HStack(alignment: .top) {
                    Image(systemName: "note.text")
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                        .padding(.top, 8)
                    TextField("Notes", text: Binding(
                        get: { card.notes ?? "" },
                        set: { card.notes = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                        .lineLimit(3...6)
                }
            }

            if !card.rawText.isEmpty {
                Section("Raw Text") {
                    Text(card.rawText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    saveToContacts()
                } label: {
                    HStack {
                        Image(systemName: contactsSaved ? "checkmark.circle.fill" : "person.crop.circle.badge.plus")
                        Text(contactsSaved ? "Saved to Contacts" : "Save to Contacts")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isSavingToContacts || contactsSaved)

                if isNewScan {
                    Button {
                        onSave?()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down.fill")
                            Text("Save Card")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if !isNewScan {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Card")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle(card.fullName.isEmpty ? "Scanned Card" : card.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete Card", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(card)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete this scanned card.")
        }
        .alert("Contacts", isPresented: .init(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .alert("Contacts Access Denied", isPresented: $showSettingsAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Contact access is denied. Please enable it in Settings to save cards to your contacts.")
        }
    }

    private func saveToContacts() {
        isSavingToContacts = true
        Task {
            do {
                try await ContactsService.saveToContacts(card)
                contactsSaved = true
            } catch is ContactsError {
                showSettingsAlert = true
            } catch {
                alertMessage = error.localizedDescription
            }
            isSavingToContacts = false
        }
    }
}

struct EditableRow: View {
    let label: String
    @Binding var text: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            TextField(label, text: $text)
        }
    }
}
