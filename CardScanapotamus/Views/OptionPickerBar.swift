import SwiftUI

/// The compact "Label: [picker] (edit)" bar shown above the card list,
/// used for both Source and Category defaults.
struct OptionPickerBar: View {
    let title: String
    let icon: String
    let tint: Color
    let options: [String]
    @Binding var selection: String
    let onManage: () -> Void

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 24)

            Text("\(title):")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if options.isEmpty {
                Text("None defined")
                    .foregroundStyle(.tertiary)
                    .font(.subheadline)
            } else {
                Picker(title, selection: $selection) {
                    Text("None").tag("")
                    ForEach(options, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            Spacer()

            Button(action: onManage) {
                Image(systemName: "pencil.circle.fill")
                    .font(.title3)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// A detail-view row that lets the user pick from defined options or type
/// freely when none are defined, with a button to add a new option inline.
struct OptionPickerRow: View {
    let title: String
    let icon: String
    let options: [String]
    @Binding var value: String?
    let onAdd: () -> Void

    private var text: Binding<String> {
        Binding(
            get: { value ?? "" },
            set: { value = $0.isEmpty ? nil : $0 }
        )
    }

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            if options.isEmpty {
                TextField(title, text: text)
            } else {
                Picker(title, selection: text) {
                    Text("None").tag("")
                    ForEach(options, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "pencil.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
        }
    }
}
