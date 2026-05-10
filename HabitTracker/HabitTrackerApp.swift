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
    let config = ModelConfiguration(schema: schema, url: groupURL)
    do {
        return try ModelContainer(for: schema, configurations: [config])
    } catch {
        fatalError("Could not create ModelContainer: \(error)")
    }
}()
