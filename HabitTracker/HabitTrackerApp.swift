    import SwiftUI
    import SwiftData
    import SQLite3

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

    // Check if all required tables exist in the store
    private func storeHasAllTables(at url: URL) -> Bool {
        let requiredTables = ["ZHABIT", "ZHABITENTRY", "ZFASTINGSESSION", "ZWEIGHTENTRY", "ZFOODENTRY"]
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_close(db) }

        for table in requiredTables {
            let query = "SELECT name FROM sqlite_master WHERE type='table' AND name='\(table)';"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return false }
            let found = sqlite3_step(stmt) == SQLITE_ROW
            sqlite3_finalize(stmt)
            if !found {
                print("Missing table: \(table)")
                return false
            }
        }
        return true
    }

    private func deleteStore(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.appendingPathExtension("shm"))
        try? FileManager.default.removeItem(at: url.appendingPathExtension("wal"))
    }

    let sharedModelContainer: ModelContainer = {
        guard let groupBase = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            fatalError("Cannot access App Group container")
        }

        let storeURL = groupBase.appendingPathComponent("HabitTracker.store")
        let schema = Schema([
            Habit.self,
            HabitEntry.self,
            FastingSession.self,
            WeightEntry.self,
            FoodEntry.self
        ])
        let config = ModelConfiguration(schema: schema, url: storeURL)

        // If store exists but is missing tables, delete it so SwiftData recreates it fresh
        if FileManager.default.fileExists(atPath: storeURL.path) {
            if !storeHasAllTables(at: storeURL) {
                print("Store is missing tables — deleting and recreating")
                deleteStore(at: storeURL)
            }
        }

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            print("ModelContainer failed, recreating store: \(error)")
            deleteStore(at: storeURL)
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

