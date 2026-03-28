import Foundation
import SwiftData

@Model
final class ScannedCard {
    var fullName: String
    var jobTitle: String
    var company: String
    var email: String
    var phone: String
    var website: String
    var address: String
    var rawText: String
    var imageData: Data?
    var scannedAt: Date
    var phone2: String?
    var phone3: String?
    var phoneType: String?
    var phone2Type: String?
    var phone3Type: String?
    var source: String?
    var notes: String?

    init(
        fullName: String = "",
        jobTitle: String = "",
        company: String = "",
        email: String = "",
        phone: String = "",
        website: String = "",
        address: String = "",
        rawText: String = "",
        imageData: Data? = nil,
        scannedAt: Date = .now,
        phone2: String? = nil,
        phone3: String? = nil,
        phoneType: String? = nil,
        phone2Type: String? = nil,
        phone3Type: String? = nil,
        source: String? = nil,
        notes: String? = nil
    ) {
        self.fullName = fullName
        self.jobTitle = jobTitle
        self.company = company
        self.email = email
        self.phone = phone
        self.website = website
        self.address = address
        self.rawText = rawText
        self.imageData = imageData
        self.scannedAt = scannedAt
        self.phone2 = phone2
        self.phone3 = phone3
        self.phoneType = phoneType
        self.phone2Type = phone2Type
        self.phone3Type = phone3Type
        self.source = source
        self.notes = notes
    }
}
