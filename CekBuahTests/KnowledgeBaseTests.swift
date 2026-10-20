import Foundation
import Testing
@testable import CekBuah

struct KnowledgeBaseTests {
    @Test func bundledFileDecodes() throws {
        let kb = try KnowledgeBase.load()
        #expect(kb.fruits.count == Fruit.allCases.count)
    }

    @Test(arguments: Fruit.allCases)
    func everyFruitIsComplete(fruit: Fruit) throws {
        let knowledge = try #require(try KnowledgeBase.load().knowledge(for: fruit))
        for state in RipenessState.allCases {
            #expect(knowledge.reasons[state.rawValue] != nil, "Alasan \(state.rawValue) belum ada untuk \(fruit)")
        }
        #expect(!knowledge.checkSteps.isEmpty)
        #expect(!knowledge.sources.isEmpty)
    }

    @Test(arguments: Fruit.allCases)
    func suggestionsUseValidStates(fruit: Fruit) throws {
        let knowledge = try #require(try KnowledgeBase.load().knowledge(for: fruit))
        for option in knowledge.checkSteps.flatMap(\.options) {
            if let raw = option.suggests {
                #expect(RipenessState(rawValue: raw) != nil, "Status tidak dikenal: \(raw)")
            }
        }
    }

    @Test func decodesMinimalJSON() throws {
        let json = """
        {"fruits":[{"id":"banana","name":"Pisang","reasons":{"matang":"Kuning."},
          "notes":[],"checkSteps":[{"id":"s","instruction":"Lihat.","options":[
          {"id":"o","label":"Kuning","suggests":"matang"},{"id":"n","label":"Lain","suggests":null}]}],
          "sources":[{"title":"t","url":"https://example.com"}]}]}
        """
        let kb = try KnowledgeBase.decode(Data(json.utf8))
        let banana = try #require(kb.knowledge(for: .banana))
        #expect(banana.reason(for: .ripe) == "Kuning.")
        #expect(banana.reason(for: .rotten) == "Belum ada penjelasan untuk status ini.")
        #expect(banana.checkSteps.first?.options.last?.suggestedState == nil)
        #expect(kb.knowledge(for: .mango) == nil)
    }

    @Test func invalidJSONThrows() {
        #expect(throws: (any Error).self) { try KnowledgeBase.decode(Data("{}".utf8)) }
    }
}

struct DaysUntilReadyTests {
    private let banana = ShelfLife(days: ["mentah": 6, "matang": 3, "busuk": 0], source: "test")

    @Test func unripeBananaWaitsThreeDays() {
        #expect(banana.daysUntilReady(fromDaysLeft: 6) == 3)
    }

    @Test func ripeOrLaterHasNoWait() {
        #expect(banana.daysUntilReady(fromDaysLeft: 3) == nil)
        #expect(banana.daysUntilReady(fromDaysLeft: 3.4) == nil)
        #expect(banana.daysUntilReady(fromDaysLeft: 0) == nil)
    }
}

struct StageConsistentEstimateTests {
    private let banana = ShelfLife(days: ["mentah": 6, "matang": 3, "busuk": 0], source: "test")
    private func p(_ unripe: Double, _ ripe: Double, _ rotten: Double) -> [ClassPrediction] {
        [ClassPrediction(state: .unripe, probability: unripe), ClassPrediction(state: .ripe, probability: ripe),
         ClassPrediction(state: .rotten, probability: rotten)]
    }

    @Test func ripeLabelNeverWaitsToRipen() throws {
        // Weighted sum would be 3.9 days ("matang 1 hari lagi"); a ripe label is capped at the ripe value.
        let days = try #require(banana.estimate(for: .ripe, from: p(0.35, 0.6, 0.05)))
        #expect(days == 3)
        #expect(banana.daysUntilReady(fromDaysLeft: days) == nil)
    }

    @Test func unripeLabelWaitsAtLeastOneDay() throws {
        let days = try #require(banana.estimate(for: .unripe, from: p(0.5, 0.45, 0.05)))
        #expect(days >= 4)
        #expect((banana.daysUntilReady(fromDaysLeft: days) ?? 0) >= 1)
    }

    @Test func rottenAndUnsureHaveNoEstimate() {
        // Weighted sum for this rotten result would be 3.1 days.
        #expect(banana.estimate(for: .rotten, from: p(0.2, 0.3, 0.5)) == nil)
        #expect(banana.estimate(for: .unsure, from: p(0.4, 0.35, 0.25)) == nil)
    }
}
