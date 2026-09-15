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
    @State private var showAddSource = false
    @State private var newSourceName = ""

    // Back-of-card capture
    @State private var showBackPrompt = false
    @State private var showBackCamera = false
    @State private var showBackPhotoPicker = false
    @State private var isProcessingBack = false
    @State private var backError: String?
    @State private var hasOfferedBack = false

    @State private var viewerItem: CardImageViewerItem?

    // Duplicate check for saved cards
    @State private var foundDuplicates: [ScannedCard] = []
    @State private var showDuplicateResult = false
    @State private var duplicatesMergedCount: Int?

    // Local copies of phone types to prevent invalid state from being written
    @State private var phoneType1: String = "Phone"
    @State private var phoneType2: String = "Cell"
    @State private var phoneType3: String = "Fax"

    var body: some View {
        withDuplicateDialogs(withBackSideDialogs(mainList))
    }

    private var mainList: some View {
        List {
            cardImagesSection

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
                CountryPickerRow(country: Binding(
                    get: { card.country ?? "" },
                    set: { card.country = $0.isEmpty ? nil : $0 }
                ))
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
                        .fixedSize()
                    }
                    Spacer()
                    Button {
                        newSourceName = ""
                        showAddSource = true
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
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

            RawTextSections(front: card.rawText, back: card.backRawText)

            actionsSection
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
        .alert("Add Source", isPresented: $showAddSource) {
            TextField("Source name", text: $newSourceName)
            Button("Add") {
                let name = newSourceName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                guard !sourceOptions.contains(where: { $0.name == name }) else { return }
                let option = SourceOption(name: name)
                modelContext.insert(option)
                card.source = name
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showContactSave) {
            ContactSaveView(contact: ContactsService.buildContact(from: card)) {
                showContactSave = false
                contactsSaved = true
            }
        }
    }

    private func withBackSideDialogs<V: View>(_ content: V) -> some View {
        content
        .task {
            // Offer to scan the back once, right after a new front scan.
            guard isNewScan, !hasOfferedBack, card.backImageData == nil else { return }
            hasOfferedBack = true
            try? await Task.sleep(for: .milliseconds(400))
            showBackPrompt = true
        }
        .overlay {
            if isProcessingBack {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    ProgressView("Scanning back of card...")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .confirmationDialog(
            backPromptTitle,
            isPresented: $showBackPrompt,
            titleVisibility: .visible
        ) {
            Button("Take Photo of Back") { showBackCamera = true }
            Button("Choose from Photos") { showBackPhotoPicker = true }
            if card.backImageData != nil {
                Button("Remove Back", role: .destructive) {
                    card.backImageData = nil
                    card.backRawText = nil
                }
            }
            Button(card.backImageData == nil ? "No Back Side" : "Cancel", role: .cancel) {}
        } message: {
            Text("Anything found on the back fills in details the front didn't have.")
        }
        .fullScreenCover(item: $viewerItem) { item in
            CardImageViewer(item: item)
        }
        .fullScreenCover(isPresented: $showBackCamera) {
            CameraView { image in
                if let image { processBackImage(image) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showBackPhotoPicker) {
            PhotoLibraryPicker { image in
                if let image { processBackImage(image) }
            }
        }
        .alert("Back Scan Failed", isPresented: .init(
            get: { backError != nil },
            set: { if !$0 { backError = nil } }
        )) {
            Button("OK") { backError = nil }
        } message: {
            Text(backError ?? "")
        }
    }

    private func withDuplicateDialogs<V: View>(_ content: V) -> some View {
        content
        .confirmationDialog(
            duplicateResultTitle,
            isPresented: $showDuplicateResult,
            titleVisibility: .visible
        ) {
            if !foundDuplicates.isEmpty {
                Button("Merge Into This Card") {
                    let count = foundDuplicates.count
                    CardMerger.absorb(foundDuplicates, into: card, context: modelContext)
                    foundDuplicates = []
                    phoneType1 = card.phoneType ?? "Phone"
                    phoneType2 = card.phone2Type ?? "Cell"
                    phoneType3 = card.phone3Type ?? "Fax"
                    duplicatesMergedCount = count
                }
            }
            Button(foundDuplicates.isEmpty ? "OK" : "Cancel", role: .cancel) { foundDuplicates = [] }
        } message: {
            Text(duplicateResultMessage)
        }
        .alert("Duplicates Merged", isPresented: .init(
            get: { duplicatesMergedCount != nil },
            set: { if !$0 { duplicatesMergedCount = nil } }
        )) {
            Button("OK") { duplicatesMergedCount = nil }
        } message: {
            Text(duplicatesMergedMessage)
        }
    }

    // MARK: - Card images

    private var cardImagesSection: some View {
        CardImagesSection(
            frontData: card.imageData,
            backData: card.backImageData,
            isBusy: isProcessingBack,
            onEditBack: { showBackPrompt = true },
            onOpen: { viewerItem = $0 }
        )
    }

    private func processBackImage(_ image: UIImage) {
        isProcessingBack = true
        Task {
            do {
                try await BackSideScanner.apply(backImage: image, to: card)
                // Pick up any phone types the back side filled in.
                phoneType1 = card.phoneType ?? "Phone"
                phoneType2 = card.phone2Type ?? "Cell"
                phoneType3 = card.phone3Type ?? "Fax"
            } catch {
                backError = error.localizedDescription
            }
            isProcessingBack = false
        }
    }

    private var backPromptTitle: String {
        card.backImageData == nil ? "Scan the back of this card?" : "Replace the back of this card?"
    }

    private var duplicateResultTitle: String {
        if foundDuplicates.isEmpty { return "No Duplicates Found" }
        return "\(foundDuplicates.count) Duplicate\(foundDuplicates.count == 1 ? "" : "s") Found"
    }

    private var duplicateResultMessage: String {
        if foundDuplicates.isEmpty {
            return "No other saved cards match this contact's email, phone, or name and company."
        }
        return duplicateSummary + "\n\nMerging keeps this card, fills in any blank fields from the others, and deletes them."
    }

    private var duplicatesMergedMessage: String {
        let n = duplicatesMergedCount ?? 0
        return "\(n) card\(n == 1 ? "" : "s") merged into this one."
    }

    private var duplicateSummary: String {
        let df = DateFormatter()
        df.dateStyle = .medium
        return foundDuplicates.prefix(5).map { dup in
            let label = [dup.fullName, dup.company].filter { !$0.isEmpty }.joined(separator: ", ")
            return "• \(label.isEmpty ? "Unnamed card" : label) (\(df.string(from: dup.scannedAt)))"
        }.joined(separator: "\n") + (foundDuplicates.count > 5 ? "\n• and \(foundDuplicates.count - 5) more" : "")
    }

    // MARK: - Actions

    private var actionsSection: some View {
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
                Button {
                    foundDuplicates = CardMerger.findDuplicates(of: card, in: modelContext)
                    showDuplicateResult = true
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Check for Duplicates")
                    }
                    .frame(maxWidth: .infinity)
                }

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

    /// Only check types for phone fields that have a number entered.
    private var activePhoneTypes: [String] {
        var types: [String] = []
        if !card.phone.isEmpty { types.append(phoneType1) }
        if !(card.phone2 ?? "").isEmpty { types.append(phoneType2) }
        if !(card.phone3 ?? "").isEmpty { types.append(phoneType3) }
        return types
    }

    private var hasDuplicatePhoneTypes: Bool {
        let types = activePhoneTypes
        return Set(types).count < types.count
    }

    private var duplicatePhoneTypeMessage: String {
        let types = activePhoneTypes
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

struct CountryPickerRow: View {
    @Binding var country: String
    @State private var showPicker = false
    @State private var searchText = ""

    private static let countries: [String] = {
        let codes = Locale.isoRegionCodes
        return codes.compactMap { code in
            Locale.current.localizedString(forRegionCode: code)
        }.sorted()
    }()

    private var filteredCountries: [String] {
        if searchText.isEmpty { return Self.countries }
        return Self.countries.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack {
                Image(systemName: "flag")
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                Text(country.isEmpty ? "Country" : country)
                    .foregroundStyle(country.isEmpty ? .tertiary : .primary)
                Spacer()
                if !country.isEmpty {
                    Button {
                        country = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                List {
                    ForEach(filteredCountries, id: \.self) { name in
                        Button {
                            country = name
                            showPicker = false
                        } label: {
                            HStack {
                                Text(name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if name == country {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search countries")
                .navigationTitle("Select Country")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showPicker = false }
                    }
                }
            }
        }
    }
}

// MARK: - Card image + raw text sections

struct CardImagesSection: View {
    let frontData: Data?
    let backData: Data?
    let isBusy: Bool
    let onEditBack: () -> Void
    let onOpen: (CardImageViewerItem) -> Void

    var body: some View {
        let front = CardImage.decode(frontData, maxPixel: 1200)
        let back = CardImage.decode(backData, maxPixel: 1200)

        if front != nil || back != nil {
            Section {
                VStack(spacing: 12) {
                    if let front {
                        CardImageThumb(image: front, label: back == nil ? nil : "Front")
                            .onTapGesture { open(frontData) }
                    }
                    if let back {
                        CardImageThumb(image: back, label: "Back")
                            .onTapGesture { open(backData) }
                    }
                }
                .frame(maxWidth: .infinity)

                Button(action: onEditBack) {
                    Label(back == nil ? "Add Back of Card" : "Replace Back of Card",
                          systemImage: back == nil ? "camera.badge.ellipsis" : "arrow.triangle.2.circlepath.camera")
                        .frame(maxWidth: .infinity)
                }
                .disabled(isBusy)
            } footer: {
                Text("Tap an image to zoom in.")
            }
        }
    }

    private func open(_ data: Data?) {
        guard let data else { return }
        onOpen(CardImageViewerItem(data: data))
    }
}

struct CardImageThumb: View {
    let image: UIImage
    let label: String?

    var body: some View {
        VStack(spacing: 4) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            if let label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct RawTextSections: View {
    let front: String
    let back: String?

    var body: some View {
        if !front.isEmpty {
            Section(back == nil ? "Raw Text" : "Raw Text (Front)") {
                rawText(front)
            }
        }
        if let back, !back.isEmpty {
            Section("Raw Text (Back)") {
                rawText(back)
            }
        }
    }

    private func rawText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }
}
