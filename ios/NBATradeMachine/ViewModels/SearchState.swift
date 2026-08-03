import SwiftUI
import Combine

/// Text for the app-level search bar that sits ABOVE the header and filters the active
/// NBA Teams / Players screen. Lives in `ContentView` (so the bar can be above the header
/// row) and is reset whenever the active screen changes.
@MainActor
final class SearchState: ObservableObject {

    // Avoid the default-MainActor isolated-deinit executor hop
    // (`swift_task_deinitOnExecutorImpl` → Swift-runtime task-local
    // double-free when released inside XCTest). No isolated teardown needed.
    nonisolated deinit {}
    @Published var text = ""
}
