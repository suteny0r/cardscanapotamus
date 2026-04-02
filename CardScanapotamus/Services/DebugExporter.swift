import UIKit

struct DebugExporter {

    /// Save the card image and OCR results to iCloud Drive/Scans folder.
    static func saveToICloud(image: UIImage, card: ScannedCard) {
        DispatchQueue.global(qos: .utility).async {
            guard let scansDir = scansDirectory() else {
                print("[DebugExporter] Failed to get scans directory")
                return
            }
            print("[DebugExporter] Saving to: \(scansDir.path)")

            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let name = card.fullName.isEmpty ? "unknown" : card.fullName
                .replacingOccurrences(of: " ", with: "_")
                .prefix(30)
            let baseName = "\(timestamp)_\(name)"

            // Save image
            if let jpegData = image.jpegData(compressionQuality: 0.9) {
                let imageURL = scansDir.appendingPathComponent("\(baseName).jpg")
                do {
                    try jpegData.write(to: imageURL)
                    print("[DebugExporter] Saved image: \(imageURL.lastPathComponent)")
                } catch {
                    print("[DebugExporter] Failed to save image: \(error)")
                }
            }

            // Save OCR results as text
            var results = "Name: \(card.fullName)\n"
            results += "Title: \(card.jobTitle)\n"
            results += "Company: \(card.company)\n"
            results += "Email: \(card.email)\n"
            results += "Phone: \(card.phone) (\(card.phoneType ?? "Phone"))\n"
            if let phone2 = card.phone2, !phone2.isEmpty {
                results += "Phone 2: \(phone2) (\(card.phone2Type ?? "Cell"))\n"
            }
            if let phone3 = card.phone3, !phone3.isEmpty {
                results += "Phone 3: \(phone3) (\(card.phone3Type ?? "Fax"))\n"
            }
            results += "Website: \(card.website)\n"
            results += "Address Line 1: \(card.addressLine1 ?? "")\n"
            results += "Address Line 2: \(card.addressLine2 ?? "")\n"
            results += "City: \(card.city ?? "")\n"
            results += "State: \(card.state ?? "")\n"
            results += "Zip: \(card.zip ?? "")\n"
            results += "Country: \(card.country ?? "")\n"
            results += "Source: \(card.source ?? "")\n"
            results += "Notes: \(card.notes ?? "")\n"
            results += "\n--- Raw Text ---\n"
            results += card.rawText

            let textURL = scansDir.appendingPathComponent("\(baseName).txt")
            do {
                try results.write(to: textURL, atomically: true, encoding: .utf8)
                print("[DebugExporter] Saved text: \(textURL.lastPathComponent)")
            } catch {
                print("[DebugExporter] Failed to save text: \(error)")
            }
        }
    }

    /// Get or create the Scans folder in the app's iCloud container.
    private static func scansDirectory() -> URL? {
        if let icloudURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            let scansDir = icloudURL.appendingPathComponent("Documents/Scans")
            do {
                try FileManager.default.createDirectory(at: scansDir, withIntermediateDirectories: true)
                print("[DebugExporter] Using iCloud container: \(scansDir.path)")
                return scansDir
            } catch {
                print("[DebugExporter] Failed to create iCloud dir: \(error)")
            }
        } else {
            print("[DebugExporter] iCloud container not available")
        }

        // Fall back to app Documents
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fallback = docs.appendingPathComponent("Scans")
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        print("[DebugExporter] Fallback to local Documents/Scans: \(fallback.path)")
        return fallback
    }
}
