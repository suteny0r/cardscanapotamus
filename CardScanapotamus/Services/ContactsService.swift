import Contacts
import ContactsUI
import SwiftUI

struct ContactsService {
    static func buildContact(from card: ScannedCard) -> CNMutableContact {
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

        let hasAddress = [card.addressLine1, card.addressLine2, card.city, card.state, card.zip]
            .contains { ($0 ?? "").isEmpty == false }
        if hasAddress {
            let postalAddress = CNMutablePostalAddress()
            var street = card.addressLine1 ?? ""
            if let line2 = card.addressLine2, !line2.isEmpty {
                street += street.isEmpty ? line2 : "\n\(line2)"
            }
            postalAddress.street = street
            postalAddress.city = card.city ?? ""
            postalAddress.state = card.state ?? ""
            postalAddress.postalCode = card.zip ?? ""
            contact.postalAddresses = [
                CNLabeledValue(label: CNLabelWork, value: postalAddress)
            ]
        }

        if let imageData = card.imageData {
            contact.imageData = imageData
        }

        return contact
    }

    private static func cnLabel(for type: String) -> String {
        switch type {
        case "Cell": return CNLabelPhoneNumberMobile
        case "Fax": return CNLabelPhoneNumberWorkFax
        default: return CNLabelPhoneNumberMain
        }
    }
}

// UIKit wrapper to present CNContactViewController
struct ContactSaveView: UIViewControllerRepresentable {
    let contact: CNMutableContact
    var onComplete: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = CNContactViewController(forNewContact: contact)
        vc.delegate = context.coordinator
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    class Coordinator: NSObject, CNContactViewControllerDelegate {
        let onComplete: () -> Void

        init(onComplete: @escaping () -> Void) {
            self.onComplete = onComplete
        }

        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            onComplete()
        }
    }
}
