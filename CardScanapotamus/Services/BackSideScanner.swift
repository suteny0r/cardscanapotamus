import UIKit

/// Handles scanning the back of a business card and merging anything it finds
/// into an existing card without overwriting fields the front already filled.
struct BackSideScanner {

    /// Run barcode + OCR recognition on the back image, store it on the card,
    /// and fill in any fields that are still empty.
    @MainActor
    static func apply(backImage: UIImage, to card: ScannedCard) async throws {
        var back = ScannedCard()

        let payloads = (try? await OCRService.detectBarcodes(in: backImage)) ?? []
        if let vcard = payloads.first(where: { VCardParser.isVCard($0) }) {
            VCardParser.apply(vcard: vcard, to: &back)
            back.rawText = vcard
        } else {
            let lines = try await OCRService.recognizeText(in: backImage)
            back = ContactParser.parse(lines: lines)
        }

        card.backImageData = backImage.jpegData(compressionQuality: 0.7)
        card.backRawText = back.rawText.isEmpty ? nil : back.rawText
        merge(back: back, into: card)
    }

    /// Copy values from `back` into `card` for every field that is currently empty.
    /// Phone numbers not already on the card are added to free slots.
    static func merge(back: ScannedCard, into card: ScannedCard) {
        if card.fullName.isEmpty { card.fullName = back.fullName }
        if card.jobTitle.isEmpty { card.jobTitle = back.jobTitle }
        if card.company.isEmpty { card.company = back.company }
        if card.email.isEmpty { card.email = back.email }
        if card.website.isEmpty { card.website = back.website }
        if card.address.isEmpty { card.address = back.address }

        // Only take the back's address if the front produced none at all,
        // so a partially parsed front address isn't mixed with a different one.
        let frontHasAddress = [card.addressLine1, card.addressLine2, card.city, card.state, card.zip]
            .contains { !($0 ?? "").isEmpty }
        if !frontHasAddress {
            card.addressLine1 = back.addressLine1
            card.addressLine2 = back.addressLine2
            card.city = back.city
            card.state = back.state
            card.zip = back.zip
        }
        if (card.country ?? "").isEmpty { card.country = back.country }

        let backPhones: [(String, String)] = [
            (back.phone, back.phoneType ?? "Phone"),
            (back.phone2 ?? "", back.phone2Type ?? "Cell"),
            (back.phone3 ?? "", back.phone3Type ?? "Fax")
        ]
        for (number, type) in backPhones where !number.isEmpty {
            addPhone(number, preferredType: type, to: card)
        }
    }

    private static func digits(_ s: String) -> String {
        s.filter(\.isNumber)
    }

    private static func addPhone(_ number: String, preferredType: String, to card: ScannedCard) {
        let existing = [card.phone, card.phone2 ?? "", card.phone3 ?? ""].map(digits)
        guard !existing.contains(digits(number)) else { return }

        var usedTypes = Set<String>()
        if !card.phone.isEmpty { usedTypes.insert(card.phoneType ?? "Phone") }
        if !(card.phone2 ?? "").isEmpty { usedTypes.insert(card.phone2Type ?? "Cell") }
        if !(card.phone3 ?? "").isEmpty { usedTypes.insert(card.phone3Type ?? "Fax") }

        let type = usedTypes.contains(preferredType)
            ? (["Phone", "Cell", "Fax"].first { !usedTypes.contains($0) } ?? preferredType)
            : preferredType

        if card.phone.isEmpty {
            card.phone = number
            card.phoneType = type
        } else if (card.phone2 ?? "").isEmpty {
            card.phone2 = number
            card.phone2Type = type
        } else if (card.phone3 ?? "").isEmpty {
            card.phone3 = number
            card.phone3Type = type
        }
    }
}
