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
        scannedAt: Date = .now
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
    }
}
