import SwiftUI

/// A single banner ad slot. Self-hiding: renders nothing when ads are disabled
/// (`AdGate.shouldShow()` == false), so callers drop it in unconditionally.
///
/// Guarded by `#if canImport(GoogleMobileAds)` — mirrors `AppCheckSetup.swift`. It
/// builds TODAY as a labeled placeholder because the GoogleMobileAds SPM product
/// isn't linked. Add that product (and a real `AppConfig.adUnitID`) to activate the
/// real banner with no change to call sites.
struct AdBannerView: View {
    var body: some View {
        if AdGate.shouldShow() {
            adContent
                .frame(maxWidth: .infinity)
                .frame(height: 50)            // standard banner height -> stable layout
        }
    }

    @ViewBuilder
    private var adContent: some View {
        #if canImport(GoogleMobileAds)
        BannerRepresentable(adUnitID: AppConfig.adUnitID)
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
            .overlay(Text("Advertisement").font(.caption2).foregroundStyle(.secondary))
    }
}

#if canImport(GoogleMobileAds)
import GoogleMobileAds

/// UIViewRepresentable wrapper for a banner. Compiled only once the GoogleMobileAds
/// SPM product is linked. NOTE: the symbol names below target the GADBannerView API;
/// adjust to the linked SDK major version if it differs (e.g. v11 dropped the `GAD`
/// prefix). This block does not affect the current build (product not linked).
private struct BannerRepresentable: UIViewRepresentable {
    let adUnitID: String
    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeBanner)
        banner.adUnitID = adUnitID
        banner.load(GADRequest())
        return banner
    }
    func updateUIView(_ uiView: GADBannerView, context: Context) {}
}
#endif

/// `List` / `Section`-styled slot for the team page (a `List` of `Section`s).
/// Self-hiding: contributes nothing to the List when ads are off.
struct AdRow: View {
    var body: some View {
        if AdGate.shouldShow() {
            Section {
                AdBannerView()
                    .listRowBackground(Color.clear)
            }
        }
    }
}

/// Free-standing slot for the player page (`ScrollView` / `VStack`).
struct AdBanner: View {
    var body: some View {
        AdBannerView()
    }
}

#Preview("Placeholder (ads on)") {
    // Note: AdBannerView reads AppConfig.adsEnabled (false by default), so this
    // preview shows the slot only if you temporarily flip the flag to true.
    VStack { AdBannerView() }.padding()
}
