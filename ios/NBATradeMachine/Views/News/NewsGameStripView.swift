import SwiftUI

/// A compact regular-season scoreboard strip for the top of the News tab. Shows
/// one day's slate as horizontally scrollable matchup cells with `‹ date ›`
/// day-stepping arrows. Renders **nothing** (zero height) unless the store is
/// `.loaded` with a selected day — so the offseason (empty window) is invisible.
struct NewsGameStripView: View {
    @ObservedObject var store: GameStripStore

    var body: some View {
        if store.phase == .loaded, let date = store.selectedDate {
            VStack(spacing: 6) {
                header(date)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(store.games(on: date), id: \.gameId) { game in
                            cell(GameStripLogic.cell(for: game))
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 6)
        } else {
            EmptyView()
        }
    }

    private func header(_ date: String) -> some View {
        HStack {
            Button { store.step(.prev) } label: { Image(systemName: "chevron.left") }
                .disabled(!store.canStep(.prev))
                .accessibilityLabel("Previous game day")
            Spacer(minLength: 8)
            Text(Self.dateLabel(date))
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Button { store.step(.next) } label: { Image(systemName: "chevron.right") }
                .disabled(!store.canStep(.next))
                .accessibilityLabel("Next game day")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal)
    }

    private func cell(_ c: GameStripCell) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                TeamLogoMark(teamId: c.awayTeamId, size: 20, showsAlias: false)
                Text(c.awayTricode).font(.caption.weight(.semibold))
                Text("vs").font(.caption2).foregroundStyle(.secondary)
                Text(c.homeTricode).font(.caption.weight(.semibold))
                TeamLogoMark(teamId: c.homeTeamId, size: 20, showsAlias: false)
            }
            Text(c.trailing)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(c.awayTricode) at \(c.homeTricode), \(c.trailing)")
    }

    /// "Sat Aug 2" style label from a "yyyy-MM-dd" string (ET-agnostic display).
    static func dateLabel(_ ymd: String) -> String {
        let inFmt = DateFormatter()
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        inFmt.timeZone = TimeZone(identifier: "UTC")
        inFmt.dateFormat = "yyyy-MM-dd"
        guard let d = inFmt.date(from: ymd) else { return ymd }
        let outFmt = DateFormatter()
        outFmt.locale = Locale(identifier: "en_US_POSIX")
        outFmt.timeZone = TimeZone(identifier: "UTC")
        outFmt.dateFormat = "EEE MMM d"
        return outFmt.string(from: d)
    }
}
