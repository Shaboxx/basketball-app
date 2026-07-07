import SwiftUI
import Combine

/// Text for the app-level search bar that sits ABOVE the header and filters the active
/// NBA Teams / Players screen. Lives in `ContentView` (so the bar can be above the header
/// row) and is reset whenever the active screen changes.
@MainActor
final class SearchState: ObservableObject {
    @Published var text = ""
}
