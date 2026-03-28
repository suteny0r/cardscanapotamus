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

        var phoneNumbers: [CNLabeledValue<CNPhoneNumber>] = []
        if !card.phone.isEmpty {
            phoneNumbers.append(CNLabeledValue(label: cnLabel(for: card.phoneType ?? "Phone"), value: CNPhoneNumber(stringValue: card.phone)))
        }
        if let phone2 = card.phone2, !phone2.isEmpty {
            phoneNumbers.append(CNLabeledValue(label: cnLabel(for: card.phone2Type ?? "Cell"), value: CNPhoneNumber(stringValue: phone2)))
        }
        if let phone3 = card.phone3, !phone3.isEmpty {
            phoneNumbers.append(CNLabeledValue(label: cnLabel(for: card.phone3Type ?? "Fax"), value: CNPhoneNumber(stringValue: phone3)))
        }
        if !phoneNumbers.isEmpty {
            contact.phoneNumbers = phoneNumbers
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

    private static func cnLabel(for type: String) -> String {
        switch type {
        case "Cell": return CNLabelPhoneNumberMobile
        case "Fax": return CNLabelPhoneNumberWorkFax
        default: return CNLabelPhoneNumberMain
        }
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
