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
        while let first = result.first, !first.isLetter && !first.isNumber && first != "+" {
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

        // Pre-split lines on bullet/separator characters (•, ·, etc.)
        // so that multiple fields on one line are processed individually
        var expandedLines: [String] = []
        for line in lines {
            let segments = line.components(separatedBy: CharacterSet(charactersIn: "•·▪"))
            for segment in segments {
                let trimmed = segment.trimmingCharacters(in: stripChars)
                if !trimmed.isEmpty { expandedLines.append(trimmed) }
            }
        }

        for line in expandedLines {
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
                addressStarted = true
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
            } else if addressStarted {
                // Once address has started, keep collecting lines that
                // don't match name/title — they're likely city, state, etc.
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
                // Last line is "City, ST 12345" format
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
                // Parts may be individually split (e.g. from • separators)
                // Try to identify each part: street, suite, city, state, country
                var streetParts: [String] = []
                for part in addressParts {
                    let cleaned = part.trimmingCharacters(in: .punctuationCharacters)
                        .trimmingCharacters(in: .whitespaces)
                    guard !cleaned.isEmpty else { continue }

                    // Check for zip code
                    if card.zip == nil, firstMatch(pattern: #"^\d{5}(?:-\d{4})?$"#, in: cleaned) != nil {
                        card.zip = cleaned
                    }
                    // Check for 2-letter state abbreviation
                    else if card.state == nil, cleaned.count == 2,
                            cleaned == cleaned.uppercased(),
                            cleaned.allSatisfy(\.isLetter) {
                        card.state = cleaned
                    }
                    // Check for country name
                    else if card.country == nil, detectCountryFromText(cleaned) != nil {
                        card.country = detectCountryFromText(cleaned)
                    }
                    // Everything else is street/city
                    else {
                        streetParts.append(cleaned)
                    }
                }
                // First street part is address line 1, rest builds city or line 2
                if !streetParts.isEmpty {
                    card.addressLine1 = streetParts[0]
                    if streetParts.count == 2 {
                        // Second part is likely the city
                        card.city = streetParts[1]
                    } else if streetParts.count > 2 {
                        card.addressLine2 = streetParts[1]
                        card.city = streetParts.dropFirst(2).joined(separator: ", ")
                    }
                }
            }
        }
        card.address = addressParts.joined(separator: ", ")

        // Detect country from multiple signals
        if card.country == nil {
            // 1. Check address lines for a country name
            for part in addressParts {
                if let country = detectCountryFromText(part) {
                    card.country = country
                    break
                }
            }
        }
        if card.country == nil {
            // 2. Check all unclaimed lines for a country name
            for (line, _) in unclaimedLines {
                if let country = detectCountryFromText(line) {
                    card.country = country
                    break
                }
            }
        }
        if card.country == nil {
            // 3. Infer from email domain suffix (e.g. .com.br → Brazil)
            card.country = detectCountryFromEmail(card.email)
        }
        if card.country == nil {
            // 4. Infer from phone country code (e.g. +55 → Brazil)
            let allPhones = [card.phone, card.phone2, card.phone3].compactMap { $0 }
            for phone in allPhones {
                if let country = detectCountryFromPhoneCode(phone) {
                    card.country = country
                    break
                }
            }
        }

        // Default to United States if no country detected
        if card.country == nil {
            card.country = "United States"
        }

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
        let pattern = #"(?:https?://)?(?:www\.)?[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+(?:/[^\s]*)?"#
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
        if firstMatch(pattern: #"^\d+\s"#, in: text) != nil { return true }
        // International street name prefixes
        let lower = text.lowercased()
        let streetPrefixes = [
            "estrada ", "rua ", "avenida ", "av ", "av. ", "alameda ", "travessa ",
            "rodovia ", "praca ", "praça ",
            "calle ", "carrera ", "paseo ", "camino ",
            "strasse ", "straße ", "gasse ",
            "rue ", "boulevard ", "allée ",
            "via ", "corso ", "piazza ", "viale ",
        ]
        return streetPrefixes.contains { lower.hasPrefix($0) }
    }

    // MARK: - Country detection

    /// Common country names and variations → standardized country name
    private static let countryNames: [String: String] = [
        "usa": "United States", "u.s.a.": "United States", "u.s.a": "United States",
        "united states": "United States", "united states of america": "United States",
        "us": "United States", "u.s.": "United States",
        "canada": "Canada",
        "mexico": "Mexico", "méxico": "Mexico",
        "uk": "United Kingdom", "u.k.": "United Kingdom",
        "united kingdom": "United Kingdom", "great britain": "United Kingdom", "england": "United Kingdom",
        "france": "France", "francia": "France",
        "germany": "Germany", "deutschland": "Germany", "alemania": "Germany",
        "italy": "Italy", "italia": "Italy",
        "spain": "Spain", "españa": "Spain",
        "portugal": "Portugal",
        "brazil": "Brazil", "brasil": "Brazil",
        "argentina": "Argentina",
        "colombia": "Colombia",
        "chile": "Chile",
        "peru": "Peru", "perú": "Peru",
        "china": "China",
        "japan": "Japan",
        "south korea": "South Korea", "korea": "South Korea",
        "india": "India",
        "australia": "Australia",
        "new zealand": "New Zealand",
        "israel": "Israel",
        "turkey": "Turkey", "türkiye": "Turkey",
        "saudi arabia": "Saudi Arabia",
        "uae": "United Arab Emirates", "u.a.e.": "United Arab Emirates",
        "united arab emirates": "United Arab Emirates",
        "netherlands": "Netherlands", "holland": "Netherlands",
        "belgium": "Belgium",
        "switzerland": "Switzerland",
        "austria": "Austria",
        "sweden": "Sweden",
        "norway": "Norway",
        "denmark": "Denmark",
        "finland": "Finland",
        "ireland": "Ireland",
        "poland": "Poland",
        "czech republic": "Czech Republic", "czechia": "Czech Republic",
        "singapore": "Singapore",
        "malaysia": "Malaysia",
        "indonesia": "Indonesia",
        "philippines": "Philippines",
        "thailand": "Thailand",
        "vietnam": "Vietnam",
        "taiwan": "Taiwan",
        "hong kong": "Hong Kong",
        "south africa": "South Africa",
        "nigeria": "Nigeria",
        "egypt": "Egypt",
        "russia": "Russia",
        "ukraine": "Ukraine",
        "greece": "Greece",
        "romania": "Romania",
        "costa rica": "Costa Rica",
        "panama": "Panama",
        "puerto rico": "Puerto Rico",
        "dominican republic": "Dominican Republic",
    ]

    /// Email ccTLD → country name
    private static let domainCountries: [String: String] = [
        "br": "Brazil", "mx": "Mexico", "ar": "Argentina", "co": "Colombia",
        "cl": "Chile", "pe": "Peru", "ve": "Venezuela", "ec": "Ecuador",
        "uk": "United Kingdom", "de": "Germany", "fr": "France", "it": "Italy",
        "es": "Spain", "pt": "Portugal", "nl": "Netherlands", "be": "Belgium",
        "ch": "Switzerland", "at": "Austria", "se": "Sweden", "no": "Norway",
        "dk": "Denmark", "fi": "Finland", "ie": "Ireland", "pl": "Poland",
        "cz": "Czech Republic", "gr": "Greece", "ro": "Romania", "ru": "Russia",
        "ua": "Ukraine", "tr": "Turkey", "il": "Israel", "sa": "Saudi Arabia",
        "ae": "United Arab Emirates", "in": "India", "cn": "China", "jp": "Japan",
        "kr": "South Korea", "tw": "Taiwan", "hk": "Hong Kong", "sg": "Singapore",
        "my": "Malaysia", "id": "Indonesia", "ph": "Philippines", "th": "Thailand",
        "vn": "Vietnam", "au": "Australia", "nz": "New Zealand", "za": "South Africa",
        "ng": "Nigeria", "eg": "Egypt", "ca": "Canada", "cr": "Costa Rica",
        "pa": "Panama", "pr": "Puerto Rico", "do": "Dominican Republic",
    ]

    /// Phone calling code → country name (most common codes)
    private static let phoneCodeCountries: [(prefix: String, country: String)] = [
        ("+1", "United States"),  // also Canada, but US is more common
        ("+44", "United Kingdom"),
        ("+33", "France"),
        ("+49", "Germany"),
        ("+39", "Italy"),
        ("+34", "Spain"),
        ("+351", "Portugal"),
        ("+55", "Brazil"),
        ("+52", "Mexico"),
        ("+54", "Argentina"),
        ("+57", "Colombia"),
        ("+56", "Chile"),
        ("+51", "Peru"),
        ("+58", "Venezuela"),
        ("+91", "India"),
        ("+86", "China"),
        ("+81", "Japan"),
        ("+82", "South Korea"),
        ("+886", "Taiwan"),
        ("+852", "Hong Kong"),
        ("+65", "Singapore"),
        ("+60", "Malaysia"),
        ("+62", "Indonesia"),
        ("+63", "Philippines"),
        ("+66", "Thailand"),
        ("+84", "Vietnam"),
        ("+61", "Australia"),
        ("+64", "New Zealand"),
        ("+972", "Israel"),
        ("+90", "Turkey"),
        ("+966", "Saudi Arabia"),
        ("+971", "United Arab Emirates"),
        ("+27", "South Africa"),
        ("+234", "Nigeria"),
        ("+20", "Egypt"),
        ("+7", "Russia"),
        ("+380", "Ukraine"),
        ("+31", "Netherlands"),
        ("+32", "Belgium"),
        ("+41", "Switzerland"),
        ("+43", "Austria"),
        ("+46", "Sweden"),
        ("+47", "Norway"),
        ("+45", "Denmark"),
        ("+358", "Finland"),
        ("+353", "Ireland"),
        ("+48", "Poland"),
        ("+420", "Czech Republic"),
        ("+30", "Greece"),
        ("+40", "Romania"),
        ("+506", "Costa Rica"),
        ("+507", "Panama"),
    ]

    private static func detectCountryFromText(_ text: String) -> String? {
        let lower = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        // Check for exact match first (whole line is a country name)
        if let country = countryNames[lower] { return country }
        // Check if a country name appears as a word boundary in the text
        for (name, country) in countryNames where name.count >= 4 {
            if lower.contains(name) { return country }
        }
        return nil
    }

    private static func detectCountryFromEmail(_ email: String) -> String? {
        guard !email.isEmpty else { return nil }
        let parts = email.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        // Check last segment as ccTLD
        let tld = String(parts.last!).lowercased()
        if let country = domainCountries[tld] { return country }
        // Check second-to-last for compound domains like .com.br
        if parts.count >= 3 {
            let secondTld = String(parts[parts.count - 1]).lowercased()
            if let country = domainCountries[secondTld] { return country }
        }
        return nil
    }

    private static func detectCountryFromPhoneCode(_ phone: String) -> String? {
        let cleaned = phone.trimmingCharacters(in: .whitespaces)
        guard cleaned.hasPrefix("+") else { return nil }
        // Sort by longest prefix first to match +886 before +88
        for entry in phoneCodeCountries.sorted(by: { $0.prefix.count > $1.prefix.count }) {
            if cleaned.hasPrefix(entry.prefix) { return entry.country }
        }
        return nil
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
