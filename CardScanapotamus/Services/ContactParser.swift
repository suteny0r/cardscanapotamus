import Foundation

struct ContactParser {

    // MARK: - Icon-based field hints

    enum FieldHint {
        case phone, email, website, address, fax, none
    }

    /// Unicode symbols commonly used as field indicators on business cards.
    /// When OCR recognizes the icon (or a visually similar character), we use
    /// it as an extra signal to classify the field that follows.
    private static let phoneIcons: Set<Character> = Set("☎☏✆📞📱🕿🕻🕾📲🕽🕼℡")
    private static let faxIcons: Set<Character> = Set("📠🖨🖷")
    private static let emailIcons: Set<Character> = Set("✉📧📩📨🖂🖃🖄🖅📬📪✍")
    private static let webIcons: Set<Character> = Set("🌐🌍🌎🌏⊕🔗")
    private static let addressIcons: Set<Character> = Set("📍📌⌂🏠🏢🗺")

    /// Detect if the first character is a known icon, return a hint and cleaned text.
    private static func detectIconHint(_ text: String) -> (hint: FieldHint, cleaned: String) {
        guard let first = text.first else { return (.none, text) }

        let hint: FieldHint
        if faxIcons.contains(first) { hint = .fax }
        else if phoneIcons.contains(first) { hint = .phone }
        else if emailIcons.contains(first) { hint = .email }
        else if webIcons.contains(first) { hint = .website }
        else if addressIcons.contains(first) { hint = .address }
        else { hint = .none }

        if hint != .none {
            let cleaned = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
            return (hint, cleaned)
        }
        return (.none, text)
    }

    /// Strip any leading non-alphanumeric character (likely a misread icon glyph).
    private static func stripLeadingGlyph(_ text: String) -> String {
        var result = text
        while let first = result.first, !first.isLetter && !first.isNumber {
            result = String(result.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    // MARK: - Main parser

    static func parse(lines: [String]) -> ScannedCard {
        var card = ScannedCard()
        card.rawText = lines.joined(separator: "\n")

        // Tracks lines with their icon hints for the second pass
        var unclaimedLines: [(text: String, hint: FieldHint)] = []

        let bulletChars = CharacterSet(charactersIn: "•·▪▸▹►▻◆◇○●■□★☆|»«›‹–—‣⁃∙※†‡§¶")
            .union(.init(charactersIn: "\u{2022}\u{2023}\u{25E6}\u{2043}\u{2219}"))
        let stripChars = bulletChars.union(.whitespacesAndNewlines)

        for line in lines {
            let stripped = line.trimmingCharacters(in: stripChars)
            guard !stripped.isEmpty else { continue }

            // Step 1: Check for recognized icon hint
            let (hint, afterIcon) = detectIconHint(stripped)

            // Step 2: Strip any remaining leading non-alphanumeric (misread glyphs)
            let trimmed = stripLeadingGlyph(afterIcon)
            guard !trimmed.isEmpty else { continue }

            // Step 3: Use hint + content extractors together
            var assigned = false

            // Icon-guided assignment — try the hinted field first
            switch hint {
            case .email:
                if card.email.isEmpty, let email = extractEmail(from: trimmed) {
                    card.email = email; assigned = true
                }
            case .website:
                if card.website.isEmpty, let website = extractWebsite(from: trimmed) {
                    card.website = website; assigned = true
                }
            case .fax:
                if let phone = extractPhone(from: trimmed) {
                    assignPhone(&card, number: phone, preferredType: "Fax")
                    assigned = true
                }
            case .phone:
                if let phone = extractPhone(from: trimmed) {
                    let textType = detectPhoneType(from: trimmed)
                    assignPhone(&card, number: phone, preferredType: textType ?? "Phone")
                    assigned = true
                }
            case .address:
                unclaimedLines.append((trimmed, .address))
                assigned = true
            case .none:
                break
            }

            if assigned { continue }

            // No icon hint matched — fall back to content-based detection
            if card.email.isEmpty, let email = extractEmail(from: trimmed) {
                card.email = email
            } else if let phone = extractPhone(from: trimmed) {
                let textType = detectPhoneType(from: trimmed)
                assignPhone(&card, number: phone, preferredType: textType ?? nextDefaultPhoneType(card))
            } else if card.website.isEmpty, let website = extractWebsite(from: trimmed) {
                card.website = website
            } else {
                unclaimedLines.append((trimmed, hint))
            }
        }

        // Second pass: assign name, title, company, address from unclaimed lines
        var nameAssigned = false
        var titleAssigned = false
        var companyAssigned = false
        var addressParts: [String] = []
        var addressStarted = false

        for (line, hint) in unclaimedLines {
            if hint == .address {
                // Icon identified this as address
                addressStarted = true
                addressParts.append(line)
            } else if addressStarted && looksLikeAddressContinuation(line) {
                addressParts.append(line)
            } else if !nameAssigned && looksLikeName(line) {
                card.fullName = line
                nameAssigned = true
                addressStarted = false
            } else if !titleAssigned && looksLikeJobTitle(line) {
                card.jobTitle = line
                titleAssigned = true
                addressStarted = false
            } else if startsWithStreetNumber(line) {
                addressStarted = true
                addressParts.append(line)
            } else if !companyAssigned {
                card.company = line
                companyAssigned = true
            }
        }

        // Parse address parts into structured fields
        if !addressParts.isEmpty {
            let lastLine = addressParts.last!
            if let cityStateZip = parseCityStateZip(lastLine) {
                card.city = cityStateZip.city
                card.state = cityStateZip.state
                card.zip = cityStateZip.zip
                let remaining = addressParts.dropLast()
                if remaining.count >= 2 {
                    card.addressLine1 = remaining.first
                    card.addressLine2 = remaining.dropFirst().joined(separator: ", ")
                } else if remaining.count == 1 {
                    card.addressLine1 = remaining.first
                }
            } else {
                card.addressLine1 = addressParts.first
                if addressParts.count > 1 {
                    card.addressLine2 = addressParts.dropFirst().joined(separator: ", ")
                }
            }
        }
        card.address = addressParts.joined(separator: ", ")
        return card
    }

    // MARK: - Phone slot assignment

    /// Assign a phone number to the first available slot, using preferredType for the label.
    private static func assignPhone(_ card: inout ScannedCard, number: String, preferredType: String) {
        if card.phone.isEmpty {
            card.phone = number
            card.phoneType = preferredType
        } else if card.phone2 == nil {
            card.phone2 = number
            card.phone2Type = preferredType
        } else if card.phone3 == nil {
            card.phone3 = number
            card.phone3Type = preferredType
        }
    }

    /// Returns the default phone type for the next empty slot.
    private static func nextDefaultPhoneType(_ card: ScannedCard) -> String {
        if card.phone.isEmpty { return "Phone" }
        if card.phone2 == nil { return "Cell" }
        return "Fax"
    }

    // MARK: - Extractors

    private static func extractEmail(from text: String) -> String? {
        let pattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        return firstMatch(pattern: pattern, in: text)
    }

    private static func detectPhoneType(from text: String) -> String? {
        let lower = text.lowercased()

        if lower.contains("fax") { return "Fax" }
        if firstMatch(pattern: #"(?:^|\s)f[\s:.\-]"#, in: lower) != nil { return "Fax" }

        if lower.contains("cell") { return "Cell" }
        if firstMatch(pattern: #"(?:^|\s)c[\s:.\-]"#, in: lower) != nil { return "Cell" }

        if lower.contains("phone") { return "Phone" }
        if firstMatch(pattern: #"(?:^|\s)p[\s:.\-]"#, in: lower) != nil { return "Phone" }

        return nil
    }

    private static func extractPhone(from text: String) -> String? {
        let phonePattern = #"[\+]?\(?[\d]{2,}[\d\s\-\.\(\)]*"#
        if let match = firstMatch(pattern: phonePattern, in: text) {
            let trimmed = match.trimmingCharacters(in: .whitespacesAndNewlines)
            let digitCount = trimmed.filter(\.isNumber).count
            if digitCount >= 7 && digitCount <= 15 {
                return trimmed
            }
        }
        return nil
    }

    private static func extractWebsite(from text: String) -> String? {
        let pattern = #"(?:https?://)?(?:www\.)?[A-Za-z0-9-]+\.[A-Za-z]{2,}(?:/[^\s]*)?"#
        if let match = firstMatch(pattern: pattern, in: text),
           match.contains("."),
           !match.contains("@") {
            return match
        }
        return nil
    }

    // MARK: - Heuristics

    private static func looksLikeName(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        return words.count >= 2
            && words.count <= 4
            && words.allSatisfy { $0.first?.isUppercase == true }
            && !text.contains(",")
            && text.filter(\.isNumber).isEmpty
    }

    private static func looksLikeJobTitle(_ text: String) -> Bool {
        let titleKeywords = [
            "manager", "director", "president", "vp", "ceo", "cto", "cfo", "coo",
            "engineer", "developer", "designer", "analyst", "consultant", "specialist",
            "coordinator", "associate", "assistant", "executive", "officer", "lead",
            "head", "chief", "founder", "partner", "senior", "junior", "sr.", "jr.",
            "supervisor", "administrator", "architect", "strategist", "representative"
        ]
        let lower = text.lowercased()
        return titleKeywords.contains { lower.contains($0) }
    }

    private static func parseCityStateZip(_ text: String) -> (city: String, state: String, zip: String)? {
        let pattern = #"^(.+?),?\s+([A-Z]{2})\s+(\d{5}(?:-\d{4})?)$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           match.numberOfRanges >= 4,
           let cityRange = Range(match.range(at: 1), in: text),
           let stateRange = Range(match.range(at: 2), in: text),
           let zipRange = Range(match.range(at: 3), in: text) {
            return (
                city: String(text[cityRange]).trimmingCharacters(in: .punctuationCharacters),
                state: String(text[stateRange]),
                zip: String(text[zipRange])
            )
        }
        let pattern2 = #"^(.+?),?\s+([A-Z]{2})$"#
        if let regex = try? NSRegularExpression(pattern: pattern2),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           match.numberOfRanges >= 3,
           let cityRange = Range(match.range(at: 1), in: text),
           let stateRange = Range(match.range(at: 2), in: text) {
            return (
                city: String(text[cityRange]).trimmingCharacters(in: .punctuationCharacters),
                state: String(text[stateRange]),
                zip: ""
            )
        }
        return nil
    }

    private static func looksLikeAddressContinuation(_ text: String) -> Bool {
        let lower = text.lowercased()
        let addressIndicators = [
            "suite", "ste.", "ste ", "unit", "apt", "floor", "fl.",
            "#", "p.o. box", "po box"
        ]
        let streetTypes = [
            "street", "st.", "avenue", "ave.", "ave ", "boulevard", "blvd.",
            "drive", "dr.", "road", "rd.", "lane", "ln.", "way", "place",
            "pl.", "court", "ct.", "circle", "cir.", "terrace", "trail",
            "parkway", "pkwy", "highway", "hwy"
        ]
        let hasIndicator = addressIndicators.contains { lower.contains($0) }
        let hasStreetType = streetTypes.contains { lower.contains($0) }
        let hasZipCode = firstMatch(pattern: #"\b\d{5}(?:-\d{4})?\b"#, in: text) != nil
        let hasStateAbbrev = firstMatch(pattern: #"\b[A-Z]{2}\b"#, in: text) != nil && text.contains(",")
        return hasIndicator || hasStreetType || hasZipCode || hasStateAbbrev
    }

    private static func startsWithStreetNumber(_ text: String) -> Bool {
        return firstMatch(pattern: #"^\d+\s"#, in: text) != nil
    }

    // MARK: - Helpers

    private static func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            return nil
        }
        return String(text[range])
    }
}
