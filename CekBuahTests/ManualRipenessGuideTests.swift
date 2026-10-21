import Testing
@testable import CekBuah

struct ManualRipenessGuideTests {
    @Test func onlyAvocadoAndMangoRequireTheHandCheck() {
        let required = ShelfFruit.allCases.filter { ManualRipenessGuide.required(for: $0) != nil }
        #expect(required == [.avocado, .mango])
    }

    @Test func everyStageHasOneAnswerPlusUnsure() {
        for guide in [ManualRipenessGuide.avocado, ManualRipenessGuide.mango] {
            #expect(guide.options.compactMap(\.stage) == [0, 1, 2, 3, 4])
            #expect(guide.options.last?.stage == nil)
        }
    }

    @Test func answersMapToAppStates() {
        let states = ManualRipenessGuide.mango.options.map(\.state)
        #expect(states == [.unripe, .unripe, .ripe, .overripe, .rotten, .unsure])
        #expect(ManualRipenessGuide.mango.options[1].stageName == "Mulai matang")
    }

    @Test func handCheckResultIsLabelled() {
        let result = ManualRipenessGuide.result(for: ManualRipenessGuide.avocado.options[2])
        #expect(result.state == .ripe)
        #expect(result.modelName == "cek manual")
        #expect(ManualRipenessGuide.result(for: ManualRipenessGuide.unsure).state == .unsure)
    }
}
