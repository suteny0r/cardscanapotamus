import SwiftUI
import SwiftData

@main
struct CardScanapotamusApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: ScannedCard.self)
    }
}
