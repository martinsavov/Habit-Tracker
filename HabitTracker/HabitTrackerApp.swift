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

private func checkpointAndVerify(at url: URL) -> Bool {
    let required = ["ZHABIT","ZHABITENTRY","ZFASTINGSESSION","ZWEIGHTENTRY","ZFOODENTRY"]
    var db: OpaquePointer?
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { return false }
    defer { sqlite3_close(db) }
    sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
    for table in required {
        let query = "SELECT name FROM sqlite_master WHERE type='table' AND name='\(table)';"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return false }
        let found = sqlite3_step(stmt) == SQLITE_ROW
        sqlite3_finalize(stmt)
        if !found { print("Missing table: \(table)"); return false }
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
        FoodEntry.self,
        FavoriteFood.self
    ])
    let config = ModelConfiguration(schema: schema, url: storeURL)

    if FileManager.default.fileExists(atPath: storeURL.path) {
        if !checkpointAndVerify(at: storeURL) {
            print("Store missing tables after checkpoint — recreating")
            deleteStore(at: storeURL)
        }
    }

    do {
        return try ModelContainer(for: schema, configurations: [config])
    } catch {
        print("ModelContainer failed — recreating: \(error)")
        deleteStore(at: storeURL)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}()
