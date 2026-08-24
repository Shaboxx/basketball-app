import SwiftUI
import WebKit

// MARK: - WKWebView UIViewRepresentable wrapper

private struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Loaded once in makeUIView; reloading here would reset scroll/sort on
        // every SwiftUI re-render.
    }
}

// MARK: - ThetaBoardView

/// Full-screen sheet showing the self-contained θ-NN Player Value Board HTML.
/// The HTML is bundled at Resources/thetaboard.html — no network calls.
struct ThetaBoardView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let url = Bundle.main.url(forResource: "thetaboard", withExtension: "html") {
                    WebView(url: url)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView(
                        "Board Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The player value board could not be loaded.")
                    )
                }
            }
            .navigationTitle("Player Value Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
