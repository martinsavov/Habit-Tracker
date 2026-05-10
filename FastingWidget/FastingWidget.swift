import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Shared App Group ID (must match HabitTrackerApp.swift)
private let appGroupID = "group.com.martinsavov.habittracker"

// MARK: - Timeline Entry

struct FastingEntry: TimelineEntry {
    let date: Date
    let startTime: Date?
    let targetHours: Double
    let planName: String
    let isActive: Bool
}

// MARK: - Timeline Provider

struct FastingProvider: TimelineProvider {

    func placeholder(in context: Context) -> FastingEntry {
        FastingEntry(date: Date(),
                     startTime: Date().addingTimeInterval(-3600 * 8),
                     targetHours: 16,
                     planName: "16:8",
                     isActive: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (FastingEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FastingEntry>) -> Void) {
        let current = entry()
        // Refresh every 5 minutes, or at the goal time if fasting
        var nextUpdate = Date().addingTimeInterval(5 * 60)
        if let start = current.startTime, current.isActive {
            let goalTime = start.addingTimeInterval(current.targetHours * 3600)
            if goalTime > Date() { nextUpdate = min(nextUpdate, goalTime) }
        }
        let timeline = Timeline(entries: [current], policy: .after(nextUpdate))
        completion(timeline)
    }

    // MARK: - Read active session from shared SwiftData store

    private func entry() -> FastingEntry {
        guard let groupContainer = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return emptyEntry()
        }

        // SwiftData stores as a .sqlite file — must match exactly what the app writes
        let storeURL = groupContainer.appendingPathComponent("HabitTracker.store")

        do {
            let schema = Schema([FastingSession.self, Habit.self, HabitEntry.self])
            let config = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)

            // Fetch all sessions and filter in memory — predicate on optional can be tricky
            let descriptor = FetchDescriptor<FastingSession>(
                sortBy: [SortDescriptor(\.startTime, order: .reverse)]
            )
            let sessions = try context.fetch(descriptor)
            let active = sessions.first { $0.endTime == nil }

            if let session = active {
                return FastingEntry(
                    date:         Date(),
                    startTime:    session.startTime,
                    targetHours:  session.targetHours,
                    planName:     session.planName,
                    isActive:     true
                )
            }
        } catch {
            print("Widget fetch error: \(error)")
        }
        return emptyEntry()
    }

    private func emptyEntry() -> FastingEntry {
        FastingEntry(date: Date(), startTime: nil, targetHours: 16, planName: "", isActive: false)
    }
}

// MARK: - Widget Views

struct FastingWidgetEntryView: View {
    let entry: FastingEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:    CircularView(entry: entry)
        case .accessoryRectangular: RectangularView(entry: entry)
        case .systemSmall:          SmallView(entry: entry)
        default:                    SmallView(entry: entry)
        }
    }
}

// MARK: Lock screen circular (ring + elapsed time)

struct CircularView: View {
    let entry: FastingEntry

    var body: some View {
        if entry.isActive, let start = entry.startTime {
            let end = start.addingTimeInterval(entry.targetHours * 3600)
            ZStack {
                ProgressView(timerInterval: start...end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)

                VStack(spacing: 0) {
                    Image(systemName: "timer")
                        .font(.system(size: 10))
                    Text(start, style: .timer)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
        } else {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 4)
                VStack(spacing: 1) {
                    Image(systemName: "timer").font(.system(size: 12))
                    Text("Start").font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: Lock screen rectangular (plan + countdown)

struct RectangularView: View {
    let entry: FastingEntry

    var body: some View {
        if entry.isActive, let start = entry.startTime {
            let end = start.addingTimeInterval(entry.targetHours * 3600)
            let reached = Date() >= end
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "timer").font(.caption2)
                    Text(entry.planName).font(.caption2).fontWeight(.semibold)
                    Spacer()
                    Text(reached ? "✓ Done" : "fasting")
                        .font(.caption2).foregroundStyle(reached ? .green : .secondary)
                }
                if reached {
                    Text("Goal reached! 🎉")
                        .font(.headline).fontWeight(.bold)
                } else {
                    Text(start, style: .timer)
                        .font(.title3).fontWeight(.bold).monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ProgressView(timerInterval: start...end, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                        .progressViewStyle(.linear)
                        .tint(.blue)
                }
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "timer").font(.title3).foregroundStyle(.secondary)
                Text("No active fast").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: Home screen small

struct SmallView: View {
    let entry: FastingEntry

    var body: some View {
        if entry.isActive, let start = entry.startTime {
            let end = start.addingTimeInterval(entry.targetHours * 3600)
            let reached = Date() >= end
            VStack(spacing: 8) {
                HStack {
                    Text("⏱").font(.title2)
                    Spacer()
                    Text(entry.planName)
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if reached {
                    Text("🎉").font(.largeTitle)
                    Text("Goal reached!").font(.caption).fontWeight(.bold).foregroundStyle(.green)
                } else {
                    Text(start, style: .timer)
                        .font(.title2).fontWeight(.bold).monospacedDigit()
                    ProgressView(timerInterval: start...end, countsDown: false)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                }
                Spacer()
            }
            .padding(12)
        } else {
            VStack(spacing: 8) {
                Text("⏱").font(.largeTitle)
                Text("Not fasting").font(.caption).foregroundStyle(.secondary)
                Text("Open app to start").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Widget Configuration

struct FastingWidget: Widget {
    let kind = "FastingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FastingProvider()) { entry in
            FastingWidgetEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Fasting Timer")
        .description("Track your fasting countdown on your lock screen or home screen.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .systemSmall
        ])
    }
}
