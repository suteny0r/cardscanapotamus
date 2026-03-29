import SwiftUI
import SwiftData

struct CardDetailView: View {
    @Bindable var card: ScannedCard
    var isNewScan: Bool = false
    var onSave: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SourceOption.createdAt) private var sourceOptions: [SourceOption]
    @State private var contactsSaved = false
    @State private var showContactSave = false
    @State private var showDeleteConfirm = false
    @State private var showDuplicateTypeAlert = false

    // Local copies of phone types to prevent invalid state from being written
    @State private var phoneType1: String = "Phone"
    @State private var phoneType2: String = "Cell"
    @State private var phoneType3: String = "Fax"

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
                PhoneRow(label: "Phone", number: $card.phone, type: $phoneType1)
                PhoneRow(label: "Phone 2", number: Binding(
                    get: { card.phone2 ?? "" },
                    set: { card.phone2 = $0.isEmpty ? nil : $0 }
                ), type: $phoneType2)
                PhoneRow(label: "Phone 3", number: Binding(
                    get: { card.phone3 ?? "" },
                    set: { card.phone3 = $0.isEmpty ? nil : $0 }
                ), type: $phoneType3)
                EditableRow(label: "Website", text: $card.website, icon: "globe")
                EditableRow(label: "Address Line 1", text: Binding(
                    get: { card.addressLine1 ?? "" },
                    set: { card.addressLine1 = $0.isEmpty ? nil : $0 }
                ), icon: "mappin.circle.fill")
                EditableRow(label: "Address Line 2", text: Binding(
                    get: { card.addressLine2 ?? "" },
                    set: { card.addressLine2 = $0.isEmpty ? nil : $0 }
                ), icon: "mappin.circle")
                EditableRow(label: "City", text: Binding(
                    get: { card.city ?? "" },
                    set: { card.city = $0.isEmpty ? nil : $0 }
                ), icon: "building")
                EditableRow(label: "State", text: Binding(
                    get: { card.state ?? "" },
                    set: { card.state = $0.isEmpty ? nil : $0 }
                ), icon: "map")
                EditableRow(label: "Zip", text: Binding(
                    get: { card.zip ?? "" },
                    set: { card.zip = $0.isEmpty ? nil : $0 }
                ), icon: "number")
            }

            if hasDuplicatePhoneTypes {
                Section {
                    Label(duplicatePhoneTypeMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
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
                        .textSelection(.enabled)
                }
            }

            Section {
                Button {
                    showContactSave = true
                } label: {
                    HStack {
                        Image(systemName: contactsSaved ? "checkmark.circle.fill" : "person.crop.circle.badge.plus")
                        Text(contactsSaved ? "Saved to Contacts" : "Save to Contacts")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(contactsSaved || hasDuplicatePhoneTypes)

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
                    .disabled(hasDuplicatePhoneTypes)
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
        .navigationBarBackButtonHidden(hasDuplicatePhoneTypes)
        .toolbar {
            if hasDuplicatePhoneTypes {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        showDuplicateTypeAlert = true
                    }
                }
            }
        }
        .onAppear {
            phoneType1 = card.phoneType ?? "Phone"
            phoneType2 = card.phone2Type ?? "Cell"
            phoneType3 = card.phone3Type ?? "Fax"
        }
        .onChange(of: phoneType1) { syncPhoneTypes() }
        .onChange(of: phoneType2) { syncPhoneTypes() }
        .onChange(of: phoneType3) { syncPhoneTypes() }
        .confirmationDialog("Delete Card", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(card)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete this scanned card.")
        }
        .alert("Duplicate Phone Types", isPresented: $showDuplicateTypeAlert) {
            Button("Discard Changes", role: .destructive) {
                phoneType1 = card.phoneType ?? "Phone"
                phoneType2 = card.phone2Type ?? "Cell"
                phoneType3 = card.phone3Type ?? "Fax"
                dismiss()
            }
            Button("Fix Now", role: .cancel) {}
        } message: {
            Text("Phone type selections have duplicates. Going back will discard your unsaved type changes. Stay to fix them.")
        }
        .sheet(isPresented: $showContactSave) {
            ContactSaveView(contact: ContactsService.buildContact(from: card)) {
                showContactSave = false
                contactsSaved = true
            }
        }
    }

    private var hasDuplicatePhoneTypes: Bool {
        let types = [phoneType1, phoneType2, phoneType3]
        return Set(types).count < types.count
    }

    private var duplicatePhoneTypeMessage: String {
        let types = [phoneType1, phoneType2, phoneType3]
        var seen = Set<String>()
        var dupes = Set<String>()
        for t in types {
            if !seen.insert(t).inserted { dupes.insert(t) }
        }
        let names = dupes.sorted().joined(separator: ", ")
        return "Each phone field must have a unique type. \"\(names)\" is assigned to more than one field."
    }

    private func syncPhoneTypes() {
        guard !hasDuplicatePhoneTypes else { return }
        card.phoneType = phoneType1
        card.phone2Type = phoneType2
        card.phone3Type = phoneType3
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

struct PhoneRow: View {
    let label: String
    @Binding var number: String
    @Binding var type: String

    private let phoneTypes = ["Phone", "Cell", "Fax"]

    var body: some View {
        HStack {
            Image(systemName: "phone.fill")
                .foregroundStyle(.blue)
                .frame(width: 24)
            TextField(label, text: $number)
            Picker("", selection: $type) {
                ForEach(phoneTypes, id: \.self) { t in
                    Text(t).tag(t)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}
