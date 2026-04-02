import SwiftUI
import SwiftData

@main
struct CardScanapotamusApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([ScannedCard.self, SourceOption.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
