import Foundation

@main
struct BasketballOfflineCommand {
    @MainActor static func main() throws {
        #if canImport(SwiftUI)
        if !CommandLine.arguments.contains("--report") {
            BasketballOfflineApp.main()
            return
        }
        #endif
        print(try OfflineReport.json())
    }
}

enum OfflineReport {
    static func json() throws -> String {
        let pool = OfflineFixtures.pool
        let quiz = try QuizEngine.initialize(definition: QuizPresets.nbaTrivia, pool: pool, seed: 42)
        let allowed = TradeCompliance.allowedIncoming(tier: .overCap, outgoing: 10_000_000, capRoom: 0)
        var draft = try RosterConstructionEngine.initialize(definition: GamePresets.createAPlayer,
            participants: [GameParticipant(id: 0, kind: .human, displayName: "Reviewer")], pool: pool, seed: 42)
        var rng = SeededRNG(seed: 42)
        while draft.status == .active {
            guard let pick = GameCPUPolicy.choosePick(draft, seat: 0, rng: &rng) else { break }
            draft = try RosterConstructionEngine.submitPick(draft, seat: 0, entityId: pick.entityId, slotId: pick.slotId)
        }
        let result: [String: Any] = ["mode": "deterministic synthetic offline demonstration",
            "players": pool.count, "teams": OfflineFixtures.teams.count,
            "quiz_questions": quiz.questions.count, "example_salary_matching_limit": allowed,
            "draft_complete": draft.status == .complete,
            "draft": draft.rosters[0].map { ["slot": $0.slotId, "player": $0.entity.name, "team": $0.entity.team] }]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

#if canImport(SwiftUI)
import SwiftUI

struct BasketballOfflineApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                OfflineRosterView().tabItem { Label("Players", systemImage: "person.3") }
                OfflineTradeView().tabItem { Label("Trades", systemImage: "arrow.left.arrow.right") }
                OfflineDraftView().tabItem { Label("Build a Team", systemImage: "list.number") }
                OfflineQuizView().tabItem { Label("Quiz", systemImage: "questionmark.circle") }
                OfflineCompareView().tabItem { Label("Higher / Lower", systemImage: "chart.bar") }
            }
            .tint(.indigo)
        }
    }
}

private struct DemoNotice: View {
    var body: some View {
        Text("OFFLINE SAMPLE · Fictional players, salaries, and ratings. These are illustrative inputs, not real player evaluations.")
            .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
    }
}

private struct OfflineRosterView: View {
    @State private var search = ""
    var filtered: [Player] {
        OfflineFixtures.players.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.position.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        NavigationStack {
            List {
                DemoNotice()
                ForEach(filtered) { player in
                    NavigationLink {
                        Form {
                            Section("Player") {
                                LabeledContent("Name", value: player.name)
                                LabeledContent("Position", value: player.position)
                                LabeledContent("Height", value: player.heightDisplay)
                                LabeledContent("Team", value: OfflineFixtures.teams.first { $0.teamId == player.teamId }!.fullName)
                            }
                            Section("Synthetic evaluation inputs") {
                                LabeledContent("Offensive contribution", value: String(format: "%.1f", player.thetaBoard?.off ?? 0))
                                LabeledContent("Defensive contribution", value: String(format: "%.1f", player.thetaBoard?.def ?? 0))
                                LabeledContent("Combined contribution", value: String(format: "%.1f", player.thetaBoard?.total ?? 0))
                            }
                            Section("Contract inputs") {
                                LabeledContent("This season", value: TradeCompliance.dollars(player.currentSalary))
                                LabeledContent("Next season", value: TradeCompliance.dollars(player.salary(forSeasonOffset: 1)))
                            }
                            DemoNotice()
                        }.navigationTitle(player.name)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(player.name).font(.headline)
                            Text("\(player.position) · \(player.teamId.capitalized) · \(TradeCompliance.dollars(player.currentSalary))")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }
            }.searchable(text: $search).navigationTitle("Basketball Workbench")
        }
    }
}

private struct OfflineTradeView: View {
    @State private var left = "sample-player-1"
    @State private var right = "sample-player-6"
    @State private var showAssessment = false
    var first: Player { OfflineFixtures.players.first { $0.slug == left }! }
    var second: Player { OfflineFixtures.players.first { $0.slug == right }! }
    var issues: [ComplianceIssue] {
        TradeCompliance.evaluate(teams: [
            OfflineFixtures.context(teamId: first.teamId, outgoing: [first], incoming: [second]),
            OfflineFixtures.context(teamId: second.teamId, outgoing: [second], incoming: [first])])
    }
    var body: some View {
        NavigationStack {
            Form {
                DemoNotice()
                Section("Propose a two-team player swap") {
                    Picker("Player sent", selection: $left) {
                        ForEach(OfflineFixtures.players) { p in Text("\(p.name) · \(p.teamId)").tag(p.slug) }
                    }
                    Picker("Player received", selection: $right) {
                        ForEach(OfflineFixtures.players) { p in Text("\(p.name) · \(p.teamId)").tag(p.slug) }
                    }
                    LabeledContent("First outgoing salary", value: TradeCompliance.dollars(first.currentSalary))
                    LabeledContent("Second outgoing salary", value: TradeCompliance.dollars(second.currentSalary))
                    Button("Review trade") { showAssessment = true }
                        .disabled(first.teamId == second.teamId)
                    if first.teamId == second.teamId { Text("Choose players from different teams.").foregroundStyle(.secondary) }
                }
                if showAssessment && first.teamId != second.teamId {
                    Section("Human review") {
                        Text(issues.contains { $0.severity == .block } ? "The rule engine found a blocking issue." : "No blocking issue in the supplied scenario.")
                            .font(.headline)
                        ForEach(issues) { issue in
                            Label(issue.message, systemImage: issue.severity == .block ? "xmark.octagon" : "exclamationmark.triangle")
                        }
                        Text("The small fixture has five players per team, so roster-minimum warnings are expected. Missing timing and exception facts are not inferred. No trade is sent or executed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Rule scope") {
                    Text("This demonstration uses the original 2025–26 rules implementation and synthetic under-cap teams. It is not a current CBA certification or a live transaction tool.")
                        .font(.caption)
                }
            }.navigationTitle("Trade Review")
        }
    }
}

private struct OfflineDraftView: View {
    @State private var state = try! RosterConstructionEngine.initialize(definition: GamePresets.createAPlayer,
        participants: [GameParticipant(id: 0, kind: .human, displayName: "You")], pool: OfflineFixtures.pool, seed: 42)
    @State private var message = ""
    var body: some View {
        NavigationStack {
            List {
                DemoNotice()
                Section("Build four complementary roles · one player per team") {
                    ForEach(state.definition.roster.slots) { slot in
                        LabeledContent(slot.label, value: state.rosters[0].first { $0.slotId == slot.id }?.entity.name ?? "Open")
                    }
                }
                if state.status == .active {
                    Section("Available players") {
                        ForEach(RosterConstructionEngine.eligibleEntities(state, seat: 0)) { player in
                            Menu("\(player.name) · \(player.team)") {
                                ForEach(RosterConstructionEngine.validSlots(state, seat: 0, entity: player)) { slot in
                                    Button("Assign to \(slot.label)") {
                                        do { state = try RosterConstructionEngine.submitPick(state, seat: 0, entityId: player.id, slotId: slot.id) }
                                        catch { message = String(describing: error) }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Section { Text("Roster complete — four roles, four distinct teams.").font(.headline) }
                }
                if !message.isEmpty { Text(message).foregroundStyle(.red) }
                Button("Reset draft") {
                    state = try! RosterConstructionEngine.initialize(definition: GamePresets.createAPlayer,
                        participants: [GameParticipant(id: 0, kind: .human, displayName: "You")], pool: OfflineFixtures.pool, seed: 42)
                    message = ""
                }
            }.navigationTitle("Build a Team")
        }
    }
}

private struct OfflineQuizView: View {
    @State private var state = try! QuizEngine.initialize(definition: QuizPresets.nbaTrivia, pool: OfflineFixtures.pool, seed: 42)
    @State private var feedback = ""
    var body: some View {
        NavigationStack {
            List {
                DemoNotice()
                LabeledContent("Score", value: "\(state.score) / \(state.questions.count)")
                if state.status == .answering, let question = state.currentQuestion {
                    Section(question.stem) {
                        ForEach(question.choices.indices, id: \.self) { index in
                            Button(question.choices[index]) {
                                let answer = question.choices[question.correctIndex]
                                state = try! QuizEngine.answer(state, choiceIndex: index)
                                feedback = state.lastAnswerCorrect == true ? "Correct." : "Correct answer: \(answer)"
                            }
                        }
                    }
                } else { Text("Quiz complete.").font(.headline) }
                if !feedback.isEmpty { Text(feedback).foregroundStyle(.secondary) }
                Button("Restart same seeded quiz") {
                    state = try! QuizEngine.initialize(definition: QuizPresets.nbaTrivia, pool: OfflineFixtures.pool, seed: 42)
                    feedback = ""
                }
            }.navigationTitle("Fixture Quiz")
        }
    }
}

private struct OfflineCompareView: View {
    @State private var state = try! CompareEngine.initialize(definition: ComparePresets.biggerContract, pool: OfflineFixtures.pool, seed: 42)
    var body: some View {
        NavigationStack {
            List {
                DemoNotice()
                LabeledContent("Correct streak", value: "\(state.score)")
                if state.status == .active {
                    Section("Which player has the larger synthetic salary?") {
                        ForEach(state.pair, id: \.self) { id in
                            Button(state.entity(id)!.name) { state = try! CompareEngine.guess(state, subjectId: id) }
                        }
                    }
                } else {
                    Text("Round complete. Review the contract inputs in Players, then try again.")
                }
                Button("Restart") { state = try! CompareEngine.initialize(definition: ComparePresets.biggerContract, pool: OfflineFixtures.pool, seed: 42) }
            }.navigationTitle("Higher / Lower")
        }
    }
}
#endif
