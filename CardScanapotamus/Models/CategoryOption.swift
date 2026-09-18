import Foundation
import SwiftData

/// A user-defined business category (e.g. "Plumbing", "Legal") a card can be tagged with.
@Model
final class CategoryOption {
    var name: String
    var createdAt: Date

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }
}
