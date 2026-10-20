import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Plain values copied from LogEntry, so exporting does not touch SwiftData off the main actor.
struct LogRow: Sendable {
    let date: Date
    let photoID: String
    let itemIndex: Int
    let itemCount: Int
    let box: String
    let estimatedDays: Double?
    let fruit: String
    let state: String
    let modelTop: String
    let confidence: Double
    let latencyMs: Int
    let isDemo: Bool
    let matchesExpectation: Bool?
    let hasPhoto: Bool
    let pickedFruit: String
    let identity: String
    let identitySuggested: String
    let identityPickedScore: Double
    let identitySuggestedScore: Double
    let identityAction: String
    let modelName: String

    init(_ entry: LogEntry) {
        date = entry.date
        photoID = entry.photoID.uuidString
        itemIndex = entry.itemIndex
        itemCount = entry.itemCount
        box = entry.boxText
        estimatedDays = entry.estimatedDays
        fruit = entry.fruitRaw
        state = entry.stateRaw
        modelTop = entry.modelTopRaw
        confidence = entry.confidence
        latencyMs = entry.latencyMs
        isDemo = entry.isDemo
        matchesExpectation = entry.matchesExpectation
        hasPhoto = entry.photoData != nil
        pickedFruit = entry.pickedFruitRaw
        identity = entry.identityRaw
        identitySuggested = entry.identitySuggestedRaw
        identityPickedScore = entry.identityPickedScore
        identitySuggestedScore = entry.identitySuggestedScore
        identityAction = entry.identityActionRaw
        modelName = entry.modelName
    }
}

enum CSVExporter {
    static let header = ["waktu", "id_foto", "buah_ke", "jumlah_buah", "kotak_xywh", "buah", "status",
                         "kelas_teratas_model", "keyakinan", "perkiraan_sisa_hari", "waktu_proses_ms", "mode_demo",
                         "sesuai", "ada_foto", "buah_dipilih", "cek_jenis", "saran_buah", "skor_buah_dipilih",
                         "skor_saran", "tindakan_penguji", "model"]

    static func csv(from rows: [LogRow]) -> String {
        let formatter = ISO8601DateFormatter()
        let lines = rows.map { row in
            [
                formatter.string(from: row.date),
                row.photoID,
                String(row.itemIndex),
                String(row.itemCount),
                row.box,
                row.fruit,
                row.state,
                row.modelTop,
                String(format: "%.4f", row.confidence),
                row.estimatedDays.map { String(format: "%.1f", $0) } ?? "",
                String(row.latencyMs),
                row.isDemo ? "ya" : "tidak",
                row.matchesExpectation.map { $0 ? "ya" : "tidak" } ?? "",
                row.hasPhoto ? "ya" : "tidak",
                row.pickedFruit,
                row.identity,
                row.identitySuggested,
                String(format: "%.3f", row.identityPickedScore),
                String(format: "%.3f", row.identitySuggestedScore),
                row.identityAction,
                row.modelName,
            ].map(escape).joined(separator: ",")
        }
        return ([header.joined(separator: ",")] + lines).joined(separator: "\n") + "\n"
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Shareable CSV file for ShareLink.
struct CSVDocument: Transferable {
    let rows: [LogRow]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { document in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("cekbuah-log.csv")
            try CSVExporter.csv(from: document.rows).write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
