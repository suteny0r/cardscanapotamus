import Foundation
import SwiftData

/// Finds existing cards that match a fresh scan and merges scan data into them.
struct CardMerger {

    /// Look for a saved card that appears to be the same person as `scan`.
    /// Matches on email, any shared phone number, or name + company.
    static func findDuplicate(of scan: ScannedCard, in context: ModelContext) -> ScannedCard? {
        let existing = (try? context.fetch(FetchDescriptor<ScannedCard>())) ?? []
        return existing.first { isSameContact($0, scan) }
    }

    /// All other saved cards that appear to be the same contact as `card`.
    static func findDuplicates(of card: ScannedCard, in context: ModelContext) -> [ScannedCard] {
        let existing = (try? context.fetch(FetchDescriptor<ScannedCard>())) ?? []
        return existing.filter { $0.persistentModelID != card.persistentModelID && isSameContact($0, card) }
    }

    /// Fold every card in `duplicates` into `card`, then delete them.
    /// Oldest scan date is kept so the merged card stays where it was in history.
    static func absorb(_ duplicates: [ScannedCard], into card: ScannedCard, context: ModelContext) {
        for dup in duplicates {
            merge(scan: dup, into: card)
            if dup.scannedAt < card.scannedAt { card.scannedAt = dup.scannedAt }
            context.delete(dup)
        }
        try? context.save()
    }

    static func isSameContact(_ a: ScannedCard, _ b: ScannedCard) -> Bool {
        let emailA = a.email.trimmingCharacters(in: .whitespaces).lowercased()
        let emailB = b.email.trimmingCharacters(in: .whitespaces).lowercased()
        if !emailA.isEmpty, emailA == emailB { return true }

        let phonesA = Set(phones(of: a))
        let phonesB = Set(phones(of: b))
        if !phonesA.isDisjoint(with: phonesB) { return true }

        let nameA = normalize(a.fullName), nameB = normalize(b.fullName)
        let compA = normalize(a.company), compB = normalize(b.company)
        if !nameA.isEmpty, nameA == nameB, !compA.isEmpty, compA == compB { return true }

        return false
    }

    /// Fill any empty field on `existing` with the value from `scan`.
    /// Existing values, including images, are never overwritten.
    static func merge(scan: ScannedCard, into existing: ScannedCard) {
        BackSideScanner.merge(back: scan, into: existing)

        if existing.imageData == nil { existing.imageData = scan.imageData }
        if existing.backImageData == nil, existing.imageData != scan.imageData {
            // A second scan of a card we already have is most often its other side.
            existing.backImageData = scan.imageData
            existing.backRawText = scan.rawText.isEmpty ? nil : scan.rawText
        }
        if (existing.source ?? "").isEmpty { existing.source = scan.source }
        if (existing.notes ?? "").isEmpty { existing.notes = scan.notes }
        if existing.rawText.isEmpty { existing.rawText = scan.rawText }
    }

    private static func phones(of card: ScannedCard) -> [String] {
        [card.phone, card.phone2 ?? "", card.phone3 ?? ""]
            .map { $0.filter(\.isNumber) }
            .filter { $0.count >= 7 }
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
