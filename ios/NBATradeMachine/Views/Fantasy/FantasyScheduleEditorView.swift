import SwiftUI

/// Commissioner Schedule editor. The head-to-head schedule is a deterministic
/// round-robin generated from the league's team order (never stored), so the ONE
/// thing a commissioner tunes here is its LENGTH: extend the round-robin to fill the
/// NBA season (it cycles, flipping home/away each pass) or trim it to a shorter run.
/// Turning "Custom length" off restores the natural single round-robin. Everything
/// stays a pure function of the members, so nothing can drift — matchups regenerate
/// whenever the roster changes. Live preview mirrors the Schedule tab exactly.
struct FantasyScheduleEditorView: View {
    @EnvironmentObject var fantasyLeagueStore: FantasyLeagueStore
    @EnvironmentObject var fantasyTeamStore: FantasyTeamStore
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let leagueId: UUID

    @State private var useCustom = false
    @State private var weeks = 1
    @State private var didAdopt = false

    private let maxWeeks = 60

    private var league: FantasyLeague? { fantasyLeagueStore.league(leagueId) }

    /// Still-existing members in league order (dangling ids skipped, like the detail view).
    private var memberTeams: [FantasyTeam] {
        (league?.teamIds ?? []).compactMap { fantasyTeamStore.team($0) }
    }
    private var teamIds: [UUID] { memberTeams.map(\.id) }

    /// Natural single round-robin length (`n-1`, or `n` padded for odd counts).
    private var baseWeeks: Int { FantasyLeagueSchedule.roundRobin(teamIds).count }

    /// Whole fantasy weeks in the NBA regular season, when the calendar is configured.
    private var calendarWeeks: Int? { appSettings.fantasyCalendar.totalWeeks }

    /// The count previewed + saved: the custom value when enabled, else nil (natural).
    private var effectiveWeeks: Int? { useCustom ? weeks : nil }

    /// Allowed custom lengths: at LEAST one full round-robin (`baseWeeks`) up to the
    /// cap. Flooring at a full round-robin keeps every team's games-played balanced —
    /// a sub-round-robin would leave some teams (odd counts) with a bye but zero games,
    /// which the raw-total standings sort would rank above a team that actually lost.
    private var stepRange: ClosedRange<Int> {
        let lo = max(1, baseWeeks)
        return lo...max(lo, maxWeeks)
    }

    private var preview: [FantasyScheduleWeek] {
        FantasyLeagueSchedule.resolved(teamIds: teamIds, regularSeasonWeeks: effectiveWeeks)
    }

    var body: some View {
        NavigationStack {
            Form {
                if memberTeams.count < 2 {
                    Section {
                        Text("Add at least two teams to this league before editing its schedule.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    lengthSection
                    previewSection
                }
            }
            .navigationTitle("Edit Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(memberTeams.count < 2)
                }
            }
            .onAppear(perform: adoptOnce)
        }
    }

    // MARK: Length

    @ViewBuilder private var lengthSection: some View {
        Section {
            Toggle("Custom regular-season length", isOn: $useCustom)
            if useCustom {
                Stepper("Regular season: \(weeks) week\(weeks == 1 ? "" : "s")",
                        value: $weeks, in: stepRange)
                if let cw = calendarWeeks, cw != weeks, stepRange.contains(cw) {
                    Button("Match NBA season (\(cw) weeks)") { weeks = cw }
                        .font(.subheadline)
                }
            }
        } header: {
            Text("Length")
        } footer: {
            Text(lengthFooter)
        }
    }

    private var lengthFooter: String {
        guard useCustom else {
            return "Off — one full round-robin (\(baseWeeks) week\(baseWeeks == 1 ? "" : "s")): every team plays each other once."
        }
        return cycleExplanation + calendarHint
    }

    /// Plain-language read of how the chosen length maps onto the round-robin.
    private var cycleExplanation: String {
        guard baseWeeks > 0 else { return "" }
        if weeks < baseWeeks {
            return "Shorter than a full round-robin — only the first \(weeks) of \(baseWeeks) matchup weeks are played, so some teams won't meet."
        }
        if weeks == baseWeeks {
            return "Exactly one round-robin — every team plays each other once."
        }
        let full = weeks / baseWeeks
        let rem = weeks % baseWeeks
        let times = rem == 0 ? "\(full)" : "\(full)–\(full + 1)"
        let tail = rem == 0
            ? "."
            : " (plus \(rem) extra week\(rem == 1 ? "" : "s"), so records are slightly uneven in the final partial cycle)."
        return "\(full) full round-robin\(full == 1 ? "" : "s")\(rem == 0 ? "" : " + \(rem)") — every team plays each other \(times) times\(tail) Home/away flips each pass."
    }

    private var calendarHint: String {
        guard let cw = calendarWeeks else { return "" }
        if weeks == cw { return "  Matches the \(cw)-week NBA regular season." }
        return "  The NBA regular season runs \(cw) fantasy weeks."
    }

    // MARK: Preview

    @ViewBuilder private var previewSection: some View {
        Section {
            ForEach(preview) { week in
                DisclosureGroup {
                    ForEach(week.pairings) { p in
                        Text("\(name(p.home))  vs  \(name(p.away))")
                            .font(.subheadline)
                    }
                    if let bye = week.bye {
                        Text("Bye: \(name(bye))").font(.caption).foregroundStyle(.secondary)
                    }
                } label: {
                    Text(weekHeader(week.index)).font(.subheadline.weight(.semibold))
                }
            }
        } header: {
            Text("Preview · \(preview.count) week\(preview.count == 1 ? "" : "s")")
        }
    }

    private func weekHeader(_ index: Int) -> String {
        let n = index + 1
        if let range = appSettings.fantasyCalendar.weekLabel(week: n) {
            return "Week \(n) · \(range)"
        }
        return "Week \(n)"
    }

    private func name(_ id: UUID) -> String { fantasyTeamStore.team(id)?.name ?? "Team" }

    // MARK: Actions

    /// Seed the controls from the stored value once (guarded so re-appearance can't
    /// clobber an in-progress edit).
    private func adoptOnce() {
        guard !didAdopt else { return }
        didAdopt = true
        if let stored = league?.rules.regularSeasonWeeks {
            useCustom = true
            weeks = clampToRange(stored)               // heals a value now below a grown round-robin
        } else {
            useCustom = false
            weeks = clampToRange(calendarWeeks ?? stepRange.lowerBound)
        }
    }

    private func clampToRange(_ x: Int) -> Int {
        min(stepRange.upperBound, max(stepRange.lowerBound, x))
    }

    private func save() {
        fantasyLeagueStore.setRegularSeasonWeeks(useCustom ? weeks : nil, in: leagueId)
        dismiss()
    }
}
