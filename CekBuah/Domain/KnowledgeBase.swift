import Foundation

/// Bundled, offline knowledge: short reasons and physical check steps per fruit.
struct KnowledgeBase: Decodable, Sendable {
    let fruits: [FruitKnowledge]

    func knowledge(for fruit: Fruit) -> FruitKnowledge? {
        fruits.first { $0.id == fruit.rawValue }
    }

    static func load(from bundle: Bundle = .main) throws -> KnowledgeBase {
        guard let url = bundle.url(forResource: "knowledge-base", withExtension: "json") else {
            throw KnowledgeBaseError.fileMissing
        }
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> KnowledgeBase {
        try JSONDecoder().decode(KnowledgeBase.self, from: data)
    }

    /// Loaded once for the whole app; empty if the file is broken (shown as missing text).
    static let shared: KnowledgeBase = (try? load()) ?? KnowledgeBase(fruits: [])
}

enum KnowledgeBaseError: Error {
    case fileMissing
}

struct FruitKnowledge: Decodable, Sendable {
    let id: String
    let name: String
    /// Keyed by RipenessState raw value (mentah, matang, ...).
    let reasons: [String: String]
    let notes: [String]
    let checkSteps: [CheckStep]
    let sources: [Source]
    /// Optional so older or minimal knowledge files still decode.
    let shelfLife: ShelfLife?

    func reason(for state: RipenessState) -> String {
        reasons[state.rawValue] ?? "Belum ada penjelasan untuk status ini."
    }
}

struct CheckStep: Decodable, Identifiable, Sendable {
    let id: String
    let instruction: String
    let options: [CheckOption]
}

struct CheckOption: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    /// Which state this answer points to (raw value), if any.
    let suggests: String?

    var suggestedState: RipenessState? { suggests.flatMap(RipenessState.init(rawValue:)) }
}

struct Source: Decodable, Sendable {
    let title: String
    let url: String
}
