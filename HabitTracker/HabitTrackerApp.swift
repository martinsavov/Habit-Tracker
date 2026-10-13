import SwiftUI
import SwiftData
import SQLite3
import UserNotifications

let appGroupID = "group.com.martinsavov.habittracker"

@main
struct HabitTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    resyncHabitNotificationsOnce(context: sharedModelContainer.mainContext)
                }
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

// MARK: - One-time notification cleanup
// Removes orphaned habit notifications left by past store wipes, then
// refreshes valid ones (same identifier = overwrite). Only touches UUID
// identifiers, so "fasting-goal" is never affected. Runs once; bump the
// key (V2, ...) to force another run after a future bulk-orphaning event.
private let resyncFlagKey = "didResyncHabitNotificationsV1"

private func resyncHabitNotificationsOnce(context: ModelContext) {
    guard !UserDefaults.standard.bool(forKey: resyncFlagKey) else { return }

    let center = UNUserNotificationCenter.current()
    guard let habits = try? context.fetch(FetchDescriptor<Habit>()) else { return }
    let habitsByID = Dictionary(habits.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })

    center.getPendingNotificationRequests { requests in
        var idsToRemove: [String] = []
        for request in requests {
            let id = request.identifier
            guard UUID(uuidString: id) != nil else { continue }
            if let habit = habitsByID[id] {
                if !habit.reminderEnabled { idsToRemove.append(id) }
            } else {
                idsToRemove.append(id)
            }
        }
        if !idsToRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: idsToRemove)
        }

        for habit in habits where habit.reminderEnabled {
            guard let time = habit.reminderTime else { continue }
            let content = UNMutableNotificationContent()
            content.title = habit.name
            content.body  = "Time to build your streak 🔥"
            content.sound = .default
            let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            center.add(UNNotificationRequest(identifier: habit.id.uuidString, content: content, trigger: trigger))
        }
        UserDefaults.standard.set(true, forKey: resyncFlagKey)
    }
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
