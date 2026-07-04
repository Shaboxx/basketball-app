import SwiftUI

/// Pure (label, z) bar row: label · centered ±bar (green right for +z, red left for
/// −z, clamped at ±3σ) · signed value. A standalone reusable port of the
/// CategoryBreakdownSection bar so FantasySections.swift is NOT modified. Used by the
/// team-profile card (§5.5) and the trade-swing card (§5.6).
struct CategoryBarRow: View {
    let label: String
    let z: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            GeometryReader { geo in
                let half = geo.size.width / 2
                // Guard non-finite z: a NaN width traps in CoreGraphics.
                let mag = min(CGFloat(z.isFinite ? abs(z) : 0) / 3.0, 1.0) * half
                ZStack(alignment: .center) {
                    Capsule().fill(Color(.tertiarySystemFill)).frame(height: 6)
                    Capsule()
                        .fill(z >= 0 ? Color.green : Color.red)
                        .frame(width: mag, height: 6)
                        .offset(x: z >= 0 ? mag / 2 : -mag / 2)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 14)
            Text(String(format: "%+.2f", z))
                .font(.caption.monospacedDigit())
                .foregroundStyle(z >= 0 ? .green : .red)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.top, 4)
    }
}
