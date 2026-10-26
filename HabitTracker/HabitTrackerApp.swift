import SwiftUI
import SwiftData
import SQLite3
import UserNotifications

let appGroupID = "group.com.martinsavov.habittracker"

@main
struct HabitTrackerApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    reconcileHabitNotifications(context: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                reconcileHabitNotifications(context: sharedModelContainer.mainContext)
            }
        }
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

// MARK: - Habit notification housekeeping
// Single source of truth: a habit notification is valid only if its
// identifier is the UUID of an existing habit with reminders switched on.
// The only other notification the app owns is "fasting-goal".

/// Cancels a habit's scheduled reminder and clears any already-delivered copy.
func cancelHabitNotifications(ids: [String]) {
    guard !ids.isEmpty else { return }
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: ids)
    center.removeDeliveredNotifications(withIdentifiers: ids)
}

/// Idempotent and removal-only: drops every pending or delivered notification
/// that does not belong to an active habit (deleted habits, reminders turned
/// off, legacy identifiers). Safe to run on every launch / foreground.
func reconcileHabitNotifications(context: ModelContext) {
    guard let habits = try? context.fetch(FetchDescriptor<Habit>()) else { return }
    let active = Set(habits.filter { $0.reminderEnabled }.map { $0.id.uuidString })
    let keep = active.union(["fasting-goal"])
    let center = UNUserNotificationCenter.current()

    center.getPendingNotificationRequests { requests in
        let stale = requests.map(\.identifier).filter { !keep.contains($0) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
    }
    center.getDeliveredNotifications { delivered in
        let stale = delivered.map(\.request.identifier).filter { !keep.contains($0) }
        if !stale.isEmpty { center.removeDeliveredNotifications(withIdentifiers: stale) }
    }
    // The app never sets a badge number, so clear any leftover one.
    center.setBadgeCount(0) { _ in }
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
