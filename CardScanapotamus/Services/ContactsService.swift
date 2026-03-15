import Contacts
import ContactsUI

struct ContactsService {
    static func saveToContacts(_ card: ScannedCard) async throws {
        let store = CNContactStore()

        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .denied || status == .restricted {
            throw ContactsError.accessDenied
        }

        let granted = try await store.requestAccess(for: .contacts)
        guard granted else {
            throw ContactsError.accessDenied
        }

        let contact = CNMutableContact()

        // Parse name
        let nameParts = card.fullName.split(separator: " ").map(String.init)
        if nameParts.count >= 2 {
            contact.givenName = nameParts[0]
            contact.familyName = nameParts.dropFirst().joined(separator: " ")
        } else if nameParts.count == 1 {
            contact.givenName = nameParts[0]
        }

        contact.jobTitle = card.jobTitle
        contact.organizationName = card.company

        if !card.email.isEmpty {
            contact.emailAddresses = [
                CNLabeledValue(label: CNLabelWork, value: card.email as NSString)
            ]
        }

        if !card.phone.isEmpty {
            contact.phoneNumbers = [
                CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: card.phone))
            ]
        }

        if !card.website.isEmpty {
            contact.urlAddresses = [
                CNLabeledValue(label: CNLabelWork, value: card.website as NSString)
            ]
        }

        if !card.address.isEmpty {
            let postalAddress = CNMutablePostalAddress()
            postalAddress.street = card.address
            contact.postalAddresses = [
                CNLabeledValue(label: CNLabelWork, value: postalAddress)
            ]
        }

        if let imageData = card.imageData {
            contact.imageData = imageData
        }

        let saveRequest = CNSaveRequest()
        saveRequest.add(contact, toContainerWithIdentifier: nil)
        try store.execute(saveRequest)
    }
}

enum ContactsError: LocalizedError {
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access to contacts was denied. Please enable it in Settings."
        }
    }
}
