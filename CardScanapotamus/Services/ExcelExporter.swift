import Foundation
import Compression

struct ExcelExporter {
    static func generateXLSX(from cards: [ScannedCard]) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let xlsxURL = tempDir.appendingPathComponent("ScannedCards.xlsx")
        try? FileManager.default.removeItem(at: xlsxURL)

        // Build shared strings
        let headers = ["Name", "Title", "Company", "Email", "Phone", "Website", "Address", "Date Scanned"]
        var sharedStrings: [String] = []
        var stringIndex: [String: Int] = [:]

        func addString(_ s: String) -> Int {
            if let idx = stringIndex[s] { return idx }
            let idx = sharedStrings.count
            sharedStrings.append(s)
            stringIndex[s] = idx
            return idx
        }

        for h in headers { _ = addString(h) }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        var rows: [[Int]] = []
        for card in cards {
            rows.append([
                addString(card.fullName),
                addString(card.jobTitle),
                addString(card.company),
                addString(card.email),
                addString(card.phone),
                addString(card.website),
                addString(card.address),
                addString(dateFormatter.string(from: card.scannedAt))
            ])
        }

        // Generate XML parts
        let contentTypes = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/><Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/><Override PartName=\"/xl/sharedStrings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml\"/></Types>"

        let rootRels = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"

        let wbRels = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/><Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"sharedStrings.xml\"/></Relationships>"

        let workbook = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Scanned Cards\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"

        let styles = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><fonts count=\"2\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font><font><b/><sz val=\"11\"/><name val=\"Calibri\"/></font></fonts><fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills><borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs><cellXfs count=\"2\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/><xf numFmtId=\"0\" fontId=\"1\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\"/></cellXfs></styleSheet>"

        // Shared strings XML
        var ssXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" count=\"\(sharedStrings.count)\" uniqueCount=\"\(sharedStrings.count)\">"
        for s in sharedStrings {
            ssXML += "<si><t>\(xmlEscape(s))</t></si>"
        }
        ssXML += "</sst>"

        // Sheet XML
        let colLetters = ["A", "B", "C", "D", "E", "F", "G", "H"]
        var sheetXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><cols>"
        let widths = [20, 25, 25, 30, 18, 25, 35, 20]
        for (i, w) in widths.enumerated() {
            sheetXML += "<col min=\"\(i+1)\" max=\"\(i+1)\" width=\"\(w)\" customWidth=\"1\"/>"
        }
        sheetXML += "</cols><sheetData><row r=\"1\">"
        for (i, _) in headers.enumerated() {
            sheetXML += "<c r=\"\(colLetters[i])1\" t=\"s\" s=\"1\"><v>\(i)</v></c>"
        }
        sheetXML += "</row>"
        for (rowIdx, row) in rows.enumerated() {
            let rowNum = rowIdx + 2
            sheetXML += "<row r=\"\(rowNum)\">"
            for (colIdx, strIdx) in row.enumerated() {
                sheetXML += "<c r=\"\(colLetters[colIdx])\(rowNum)\" t=\"s\"><v>\(strIdx)</v></c>"
            }
            sheetXML += "</row>"
        }
        sheetXML += "</sheetData></worksheet>"

        // Build ZIP file manually with entries at root level
        var zipWriter = ZIPWriter()
        try zipWriter.addEntry(path: "[Content_Types].xml", data: Data(contentTypes.utf8))
        try zipWriter.addEntry(path: "_rels/.rels", data: Data(rootRels.utf8))
        try zipWriter.addEntry(path: "xl/_rels/workbook.xml.rels", data: Data(wbRels.utf8))
        try zipWriter.addEntry(path: "xl/workbook.xml", data: Data(workbook.utf8))
        try zipWriter.addEntry(path: "xl/styles.xml", data: Data(styles.utf8))
        try zipWriter.addEntry(path: "xl/sharedStrings.xml", data: Data(ssXML.utf8))
        try zipWriter.addEntry(path: "xl/worksheets/sheet1.xml", data: Data(sheetXML.utf8))
        let zipData = zipWriter.finalize()

        try zipData.write(to: xlsxURL)
        return xlsxURL
    }

    private static func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - Minimal ZIP Writer (PKZIP 2.0 compatible, STORE method)

private struct ZIPWriter {
    private var centralDirectory: Data = Data()
    private var body: Data = Data()
    private var entryCount: UInt16 = 0

    mutating func addEntry(path: String, data: Data) throws {
        let pathData = Data(path.utf8)
        let crc = crc32(data)
        let offset = UInt32(body.count)

        // Local file header
        var local = Data()
        local.appendUInt32(0x04034B50)       // Local file header signature
        local.appendUInt16(20)                // Version needed (2.0)
        local.appendUInt16(0)                 // General purpose bit flag
        local.appendUInt16(0)                 // Compression method: STORE
        local.appendUInt16(0)                 // Last mod file time
        local.appendUInt16(0)                 // Last mod file date
        local.appendUInt32(crc)               // CRC-32
        local.appendUInt32(UInt32(data.count)) // Compressed size
        local.appendUInt32(UInt32(data.count)) // Uncompressed size
        local.appendUInt16(UInt16(pathData.count)) // File name length
        local.appendUInt16(0)                 // Extra field length
        local.append(pathData)                // File name
        local.append(data)                    // File data
        body.append(local)

        // Central directory entry
        var cd = Data()
        cd.appendUInt32(0x02014B50)           // Central directory signature
        cd.appendUInt16(20)                   // Version made by
        cd.appendUInt16(20)                   // Version needed
        cd.appendUInt16(0)                    // General purpose bit flag
        cd.appendUInt16(0)                    // Compression method: STORE
        cd.appendUInt16(0)                    // Last mod file time
        cd.appendUInt16(0)                    // Last mod file date
        cd.appendUInt32(crc)                  // CRC-32
        cd.appendUInt32(UInt32(data.count))   // Compressed size
        cd.appendUInt32(UInt32(data.count))   // Uncompressed size
        cd.appendUInt16(UInt16(pathData.count)) // File name length
        cd.appendUInt16(0)                    // Extra field length
        cd.appendUInt16(0)                    // File comment length
        cd.appendUInt16(0)                    // Disk number start
        cd.appendUInt16(0)                    // Internal file attributes
        cd.appendUInt32(0)                    // External file attributes
        cd.appendUInt32(offset)               // Relative offset of local header
        cd.append(pathData)                   // File name
        centralDirectory.append(cd)

        entryCount += 1
    }

    func finalize() -> Data {
        var result = body
        let cdOffset = UInt32(result.count)
        result.append(centralDirectory)
        let cdSize = UInt32(centralDirectory.count)

        // End of central directory record
        var eocd = Data()
        eocd.appendUInt32(0x06054B50)         // EOCD signature
        eocd.appendUInt16(0)                  // Disk number
        eocd.appendUInt16(0)                  // Disk with central directory
        eocd.appendUInt16(entryCount)         // Entries on this disk
        eocd.appendUInt16(entryCount)         // Total entries
        eocd.appendUInt32(cdSize)             // Size of central directory
        eocd.appendUInt32(cdOffset)           // Offset of central directory
        eocd.appendUInt16(0)                  // Comment length
        result.append(eocd)

        return result
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 == 1 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }

    mutating func appendUInt32(_ value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
}
