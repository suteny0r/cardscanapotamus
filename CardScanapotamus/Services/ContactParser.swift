import Foundation

struct ContactParser {
    static func parse(lines: [String]) -> ScannedCard {
        var card = ScannedCard()
        card.rawText = lines.joined(separator: "\n")

        var unclaimedLines: [String] = []

        // Characters commonly used as bullet/separator glyphs on business cards
        let bulletChars = CharacterSet(charactersIn: "•·▪▸▹►▻◆◇○●■□★☆|»«›‹–—‣⁃∙※†‡§¶")
            .union(.init(charactersIn: "\u{2022}\u{2023}\u{25E6}\u{2043}\u{2219}"))
        let stripChars = bulletChars.union(.whitespacesAndNewlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: stripChars)
            guard !trimmed.isEmpty else { continue }

            if card.email.isEmpty, let email = extractEmail(from: trimmed) {
                card.email = email
            } else if card.phone.isEmpty, let phone = extractPhone(from: trimmed) {
                card.phone = phone
                card.phoneType = detectPhoneType(from: trimmed) ?? "Phone"
            } else if card.phone2 == nil, let phone2 = extractPhone(from: trimmed) {
                card.phone2 = phone2
                card.phone2Type = detectPhoneType(from: trimmed) ?? "Cell"
            } else if card.phone3 == nil, let phone3 = extractPhone(from: trimmed) {
                card.phone3 = phone3
                card.phone3Type = detectPhoneType(from: trimmed) ?? "Fax"
            } else if card.website.isEmpty, let website = extractWebsite(from: trimmed) {
                card.website = website
            } else {
                unclaimedLines.append(trimmed)
            }
        }

        // Heuristics for unclaimed lines:
        // - First unclaimed line is likely the name
        // - Lines with common title keywords are job titles
        // - Longer lines with commas or numbers may be addresses
        // - Remaining short lines may be company names

        var nameAssigned = false
        var titleAssigned = false
        var companyAssigned = false
        var addressParts: [String] = []
        var addressStarted = false

        for line in unclaimedLines {
            if addressStarted && looksLikeAddressContinuation(line) {
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

        card.address = addressParts.joined(separator: ", ")
        return card
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
        // Phone must start with (, +, or 2+ consecutive digits
        let phonePattern = #"[\+]?\(?[\d]{2,}[\d\s\-\.\(\)]*"#
        if let match = firstMatch(pattern: phonePattern, in: text) {
            let trimmed = match.trimmingCharacters(in: .whitespacesAndNewlines)
            let digitCount = trimmed.filter(\.isNumber).count
            // Require at least 7 digits in the match itself to avoid
            // grabbing street numbers (e.g. "20725") as phone numbers
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
        // Names are typically 2-4 words, all capitalized, no special chars
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

    private static func looksLikeAddressContinuation(_ text: String) -> Bool {
        // Lines that continue an address: suite/unit lines, city/state/zip lines
        let lower = text.lowercased()
        let addressIndicators = [
            "suite", "ste.", "ste ", "unit", "apt", "floor", "fl.",
            "#", "p.o. box", "po box"
        ]
        let hasIndicator = addressIndicators.contains { lower.contains($0) }
        let hasZipCode = firstMatch(pattern: #"\b\d{5}(?:-\d{4})?\b"#, in: text) != nil
        let hasStateAbbrev = firstMatch(pattern: #"\b[A-Z]{2}\b"#, in: text) != nil && text.contains(",")
        return hasIndicator || hasZipCode || hasStateAbbrev
    }

    private static func startsWithStreetNumber(_ text: String) -> Bool {
        // Address lines start with a street number (digits at the beginning)
        // e.g. "20725 NE 16 Ave.", "123 Main St.", "1 Broadway"
        return firstMatch(pattern: #"^\d+\s"#, in: text) != nil
    }

    private static func looksLikeAddress(_ text: String) -> Bool {
        let addressIndicators = [
            "street", "st.", "avenue", "ave.", "boulevard", "blvd.", "drive", "dr.",
            "road", "rd.", "lane", "ln.", "suite", "ste.", "floor", "fl.",
            "#", "p.o. box", "po box"
        ]
        let lower = text.lowercased()
        let hasIndicator = addressIndicators.contains { lower.contains($0) }
        let hasZipCode = firstMatch(pattern: #"\b\d{5}(?:-\d{4})?\b"#, in: text) != nil
        let hasStateAbbrev = firstMatch(pattern: #"\b[A-Z]{2}\b"#, in: text) != nil && text.contains(",")

        return hasIndicator || hasZipCode || (hasStateAbbrev && text.count > 10)
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
