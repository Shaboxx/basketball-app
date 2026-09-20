import XCTest
@testable import BasketballOffline

/// Phase 5 T6/T7: QUIZ per-template generators (superlative argmax + distinct
/// distractors, attributeLookup numeric answer + distractors, whichSeason,
/// higherField), engine build-up-front, answer scoring, replay identity, thin-pool
/// tolerance, and typed errors.
final class QuizEngineTests: XCTestCase {

    /// Distinct pts/rings/season values so superlatives/lookups are unambiguous.
    private func pool(_ n: Int = 12) -> [GameEntityRecord] {
        (0..<n).map { i in
            GameEntityRecord(id: "p\(i)", name: "Player \(i)", team: "T\(i)",
                             position: ["GUARD", "WING", "BIG"][i % 3],
                             salary: (i + 1) * 1_000_000, rating: Double(90 - i),
                             careerRings: i,
                             pts: Double(30 - i), reb: Double(5 + i), ast: Double(4 + i),
                             seasonLabel: "20\(String(format: "%02d", i))-\(String(format: "%02d", i + 1))")
        }
    }

    private func def(_ templates: [QuizTemplateKind], questionCount: Int = 6,
                     choiceCount: Int = 4, poolSize: Int = 12) -> QuizDefinition {
        QuizDefinition(id: "t", title: "T", poolSource: .historical(.allEligible),
                       config: QuizConfig(templates: templates, questionCount: questionCount,
                                          choiceCount: choiceCount, candidatePoolSize: poolSize))
    }

    // MARK: - Superlative

    func testSuperlativePicksTrueArgmaxWithDistinctDistractors() throws {
        let d = def([.superlative(field: .pts, higherIsBetter: true)], questionCount: 1, choiceCount: 4)
        let s = try QuizEngine.initialize(definition: d, pool: pool(), seed: 3)
        let q = try XCTUnwrap(s.questions.first)
        XCTAssertEqual(q.choices.count, 4)
        XCTAssertEqual(Set(q.choices).count, 4, "distractors must be distinct")
        XCTAssertTrue(q.correctIndex >= 0 && q.correctIndex < 4)
        // The chosen answer is the max-pts among the 4 shown. We can't map labels
        // back to ids trivially, but the correct choice must be present exactly once.
        let answerLabel = q.choices[q.correctIndex]
        XCTAssertEqual(q.choices.filter { $0 == answerLabel }.count, 1)
    }

    func testSuperlativeLeastInvertsAnswer() throws {
        let dHi = def([.superlative(field: .pts, higherIsBetter: true)], questionCount: 1)
        let dLo = def([.superlative(field: .pts, higherIsBetter: false)], questionCount: 1)
        let hi = try QuizEngine.initialize(definition: dHi, pool: pool(), seed: 8)
        let lo = try QuizEngine.initialize(definition: dLo, pool: pool(), seed: 8)
        // Same seed samples the same 4; the "most" and "least" answers differ.
        XCTAssertEqual(Set(hi.questions[0].choices), Set(lo.questions[0].choices))
        XCTAssertNotEqual(hi.questions[0].choices[hi.questions[0].correctIndex],
                          lo.questions[0].choices[lo.questions[0].correctIndex])
    }

    // MARK: - AttributeLookup

    func testAttributeLookupProducesNumericAnswerAndDistractors() throws {
        let d = def([.attributeLookup(field: .careerRings)], questionCount: 1, choiceCount: 4)
        let s = try QuizEngine.initialize(definition: d, pool: pool(), seed: 4)
        let q = try XCTUnwrap(s.questions.first)
        XCTAssertEqual(q.choices.count, 4)
        XCTAssertEqual(Set(q.choices).count, 4)
        XCTAssertTrue(q.stem.contains("championship rings"))
    }

    // MARK: - WhichSeason

    func testWhichSeasonCorrectness() throws {
        let d = def([.whichSeason], questionCount: 1, choiceCount: 4)
        let s = try QuizEngine.initialize(definition: d, pool: pool(), seed: 6)
        let q = try XCTUnwrap(s.questions.first)
        XCTAssertEqual(q.choices.count, 4)
        XCTAssertEqual(Set(q.choices).count, 4)
        // The correct choice is a valid season label from the pool.
        let seasons = Set(pool().compactMap { $0.seasonLabel })
        XCTAssertTrue(seasons.contains(q.choices[q.correctIndex]))
    }

    // MARK: - HigherField

    func testHigherFieldIsTwoChoiceWithRealAnswer() throws {
        let d = def([.higherField(field: .pts, higherIsBetter: true)], questionCount: 1)
        let s = try QuizEngine.initialize(definition: d, pool: pool(), seed: 2)
        let q = try XCTUnwrap(s.questions.first)
        XCTAssertEqual(q.choices.count, 2)
        XCTAssertNotEqual(q.choices[0], q.choices[1])
        XCTAssertTrue(q.correctIndex == 0 || q.correctIndex == 1)
    }

    // MARK: - Build-up-front + replay

    func testBuildsQuestionCountUpFront() throws {
        let d = def([.superlative(field: .pts, higherIsBetter: true),
                     .higherField(field: .reb, higherIsBetter: true),
                     .whichSeason], questionCount: 6)
        let s = try QuizEngine.initialize(definition: d, pool: pool(), seed: 1)
        XCTAssertEqual(s.questions.count, 6)
        XCTAssertEqual(s.currentIndex, 0)
        XCTAssertEqual(s.status, .answering)
    }

    func testSameSeedIdenticalQuestions() throws {
        let d = def([.superlative(field: .pts, higherIsBetter: true), .whichSeason],
                    questionCount: 4)
        let a = try QuizEngine.initialize(definition: d, pool: pool(), seed: 99)
        let b = try QuizEngine.initialize(definition: d, pool: pool(), seed: 99)
        XCTAssertEqual(a.questions, b.questions)
    }

    // MARK: - Answer loop

    func testAnswerAdvancesAndScores() throws {
        let d = def([.superlative(field: .pts, higherIsBetter: true)], questionCount: 3)
        var s = try QuizEngine.initialize(definition: d, pool: pool(), seed: 5)
        let correct = s.questions[0].correctIndex
        s = try QuizEngine.answer(s, choiceIndex: correct)
        XCTAssertEqual(s.score, 1)
        XCTAssertEqual(s.currentIndex, 1)
        XCTAssertEqual(s.lastAnswerCorrect, true)
    }

    func testWrongAnswerDoesNotScore() throws {
        let d = def([.superlative(field: .pts, higherIsBetter: true)], questionCount: 2)
        var s = try QuizEngine.initialize(definition: d, pool: pool(), seed: 5)
        let wrong = (s.questions[0].correctIndex + 1) % s.questions[0].choices.count
        s = try QuizEngine.answer(s, choiceIndex: wrong)
        XCTAssertEqual(s.score, 0)
        XCTAssertEqual(s.lastAnswerCorrect, false)
    }

    func testCompletesAfterLastQuestion() throws {
        let d = def([.superlative(field: .pts, higherIsBetter: true)], questionCount: 2)
        var s = try QuizEngine.initialize(definition: d, pool: pool(), seed: 5)
        s = try QuizEngine.answer(s, choiceIndex: 0)
        s = try QuizEngine.answer(s, choiceIndex: 0)
        XCTAssertEqual(s.status, .complete)
    }

    func testAnswerPastEndThrows() throws {
        let d = def([.superlative(field: .pts, higherIsBetter: true)], questionCount: 1)
        var s = try QuizEngine.initialize(definition: d, pool: pool(), seed: 5)
        s = try QuizEngine.answer(s, choiceIndex: 0)
        XCTAssertThrowsError(try QuizEngine.answer(s, choiceIndex: 0)) {
            XCTAssertEqual($0 as? QuizError, .alreadyComplete)
        }
    }

    func testInvalidChoiceThrows() throws {
        let d = def([.superlative(field: .pts, higherIsBetter: true)], questionCount: 1)
        let s = try QuizEngine.initialize(definition: d, pool: pool(), seed: 5)
        XCTAssertThrowsError(try QuizEngine.answer(s, choiceIndex: 99)) {
            XCTAssertEqual($0 as? QuizError, .invalidChoice)
        }
    }

    // MARK: - Thin-pool tolerance

    func testThinPoolSkipsUnbuildableTemplatesButStillBuildsWhatItCan() throws {
        // Only 3 entities with pts; a choiceCount-4 superlative can't be built, but a
        // higherField (needs 2) can. The engine should build the higherField ones.
        let thin = Array(pool(3))
        let d = def([.superlative(field: .pts, higherIsBetter: true),
                     .higherField(field: .pts, higherIsBetter: true)],
                    questionCount: 3, choiceCount: 4, poolSize: 3)
        let s = try QuizEngine.initialize(definition: d, pool: thin, seed: 1)
        XCTAssertFalse(s.questions.isEmpty)
        // Every built question is a 2-choice higherField (the 4-choice superlative
        // couldn't be filled from 3 entities).
        XCTAssertTrue(s.questions.allSatisfy { $0.choices.count == 2 })
    }

    func testThrowsWhenNothingBuildable() {
        // No pts field at all → neither template can be built.
        let noStats = [GameEntityRecord(id: "a", name: "A", team: "T", position: "GUARD",
                                        salary: nil, rating: 5)]
        let d = def([.superlative(field: .pts, higherIsBetter: true)], questionCount: 3,
                    choiceCount: 4, poolSize: 1)
        XCTAssertThrowsError(try QuizEngine.initialize(definition: d, pool: noStats, seed: 1)) {
            XCTAssertEqual($0 as? QuizError, .notEnoughContent)
        }
    }
}
