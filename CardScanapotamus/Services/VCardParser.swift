import Foundation

/// Parses vCard (VCF) data from QR codes and applies fields to a ScannedCard.
/// vCard fields take priority over OCR-parsed fields when present.
struct VCardParser {

    /// Parse vCard string and apply all fields to the card.
    static func apply(vcard: String, to card: inout ScannedCard) {
        card.rawText = vcard
        let lines = unfoldLines(vcard)

        for line in lines {
            let (property, value) = parseLine(line)
            guard !value.isEmpty else { continue }

            // Extract base property name (before any ;PARAMS)
            let baseName = property.split(separator: ";").first.map(String.init)?.uppercased() ?? property.uppercased()

            switch baseName {
            case "FN":
                card.fullName = value
            case "N":
                // N:Last;First;Middle;Prefix;Suffix
                let parts = value.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
                let first = parts.count > 1 ? parts[1] : ""
                let last = parts.count > 0 ? parts[0] : ""
                let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
                if !name.isEmpty { card.fullName = name }
            case "ORG":
                card.company = value.replacingOccurrences(of: ";", with: " ").trimmingCharacters(in: .whitespaces)
            case "TITLE":
                card.jobTitle = value
            case "EMAIL":
                if card.email.isEmpty { card.email = value }
            case "URL":
                if card.website.isEmpty { card.website = value }
            case "NOTE":
                card.notes = value
            case "TEL":
                assignPhone(property: property, value: value, card: &card)
            case "ADR":
                parseAddress(value: value, card: &card)
            default:
                break
            }
        }
    }

    /// Check if a string looks like vCard data.
    static func isVCard(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.uppercased().hasPrefix("BEGIN:VCARD")
    }

    // MARK: - Private

    /// Unfold continuation lines per RFC 6350 (lines starting with space/tab
    /// are continuations of the previous line).
    private static func unfoldLines(_ text: String) -> [String] {
        var result: [String] = []
        for line in text.components(separatedBy: .newlines) {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")) && !result.isEmpty {
                result[result.count - 1] += String(line.dropFirst())
            } else {
                result.append(line)
            }
        }
        return result
    }

    /// Split a vCard line into property name and value.
    private static func parseLine(_ line: String) -> (property: String, value: String) {
        // Format: PROPERTY;PARAMS:VALUE or PROPERTY:VALUE
        guard let colonIdx = line.firstIndex(of: ":") else { return ("", "") }
        let property = String(line[line.startIndex..<colonIdx])
        let value = String(line[line.index(after: colonIdx)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (property, value)
    }

    /// Detect phone type from TEL property parameters and assign to correct slot.
    private static func assignPhone(property: String, value: String, card: inout ScannedCard) {
        let upper = property.uppercased()
        let type: String
        if upper.contains("FAX") {
            type = "Fax"
        } else if upper.contains("CELL") || upper.contains("MOBILE") {
            type = "Cell"
        } else {
            type = "Phone"
        }

        // Assign to first available slot, preferring matching type
        if card.phone.isEmpty {
            card.phone = value
            card.phoneType = type
        } else if card.phone2 == nil {
            card.phone2 = value
            card.phone2Type = type
        } else if card.phone3 == nil {
            card.phone3 = value
            card.phone3Type = type
        }
    }

    /// Parse ADR field: ADR:PO Box;Extended;Street;City;State;Zip;Country
    private static func parseAddress(value: String, card: inout ScannedCard) {
        let parts = value.split(separator: ";", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        // Index: 0=PO Box, 1=Extended/Apt, 2=Street, 3=City, 4=State, 5=Zip, 6=Country
        if parts.count > 2 && !parts[2].isEmpty { card.addressLine1 = parts[2] }
        if parts.count > 1 && !parts[1].isEmpty { card.addressLine2 = parts[1] }
        if parts.count > 0 && !parts[0].isEmpty {
            // PO Box — append to line2 if present
            if card.addressLine2 == nil || card.addressLine2!.isEmpty {
                card.addressLine2 = parts[0]
            }
        }
        if parts.count > 3 && !parts[3].isEmpty { card.city = parts[3] }

        let stateVal = parts.count > 4 ? parts[4] : ""
        let countryVal = parts.count > 6 ? parts[6] : ""

        if !stateVal.isEmpty && countryVal.isEmpty && isCountryName(stateVal) {
            // vCard placed country in the state/region slot with empty country field
            card.country = stateVal
        } else {
            if !stateVal.isEmpty { card.state = stateVal }
            if !countryVal.isEmpty { card.country = countryVal }
        }

        if parts.count > 5 && !parts[5].isEmpty { card.zip = parts[5] }
    }

    /// Check if a string is a recognized country name using Locale data.
    private static func isCountryName(_ text: String) -> Bool {
        let codes = Locale.isoRegionCodes
        return codes.contains { code in
            guard let name = Locale.current.localizedString(forRegionCode: code) else { return false }
            return name.caseInsensitiveCompare(text) == .orderedSame
        }
    }
}
