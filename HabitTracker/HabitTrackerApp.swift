import SwiftUI
import SwiftData

// App Group identifier — must match exactly what you create in Xcode
let appGroupID = "group.com.martinsavov.habittracker"

@main
struct HabitTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}

// Shared container used by both the app and the widget extension
let sharedModelContainer: ModelContainer = {
    let schema = Schema([Habit.self, HabitEntry.self, FastingSession.self])
    let groupURL = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)!
        .appendingPathComponent("HabitTracker.store")
    // allowsSave: true + no version spec = SwiftData handles lightweight migration automatically
    let config = ModelConfiguration(schema: schema, url: groupURL)
    do {
        return try ModelContainer(for: schema, configurations: [config])
    } catch {
        // If migration fails, try destroying and recreating the store
        // This preserves app stability at the cost of data — better than a crash
        print("ModelContainer error: \(error). Attempting recovery...")
        let recoveryConfig = ModelConfiguration(schema: schema, url: groupURL, allowsSave: true)
        do {
            return try ModelContainer(for: schema, configurations: [recoveryConfig])
        } catch {
            fatalError("Could not create ModelContainer even after recovery: \(error)")
        }
    }
}()
