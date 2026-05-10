import SwiftData
import SwiftUI

// MARK: - Day order (Mon=0 … Sun=6, European standard)
// Calendar.weekday returns 1=Sun … 7=Sat
// Conversion: (weekday + 5) % 7  →  Mon=0, Tue=1, … Sun=6
func habitWeekday(from date: Date) -> Int {
    let w = Calendar.current.component(.weekday, from: date) // 1=Sun…7=Sat
    return (w + 5) % 7  // Mon=0, Tue=1, Wed=2, Thu=3, Fri=4, Sat=5, Sun=6
}

@Model
final class Habit {
    var id: UUID
    var name: String
    var emoji: String
    var colorHex: String
    var frequency: [Int]        // 0=Mon … 6=Sun
    var reminderTime: Date?
    var reminderEnabled: Bool
    var createdAt: Date
    var sortOrder: Int

    @Relationship(deleteRule: .cascade)
    var entries: [HabitEntry] = []

    init(
        name: String,
        emoji: String           = "⭐",
        colorHex: String        = "#0A84FF",   // iOS system blue
        frequency: [Int]        = [0,1,2,3,4,5,6],
        reminderTime: Date?     = nil,
        reminderEnabled: Bool   = false,
        sortOrder: Int          = 0
    ) {
        self.id              = UUID()
        self.name            = name
        self.emoji           = emoji
        self.colorHex        = colorHex
        self.frequency       = frequency
        self.reminderTime    = reminderTime
        self.reminderEnabled = reminderEnabled
        self.createdAt       = Date()
        self.sortOrder       = sortOrder
    }

    var color: Color {
        Color(hex: colorHex) ?? .blue
    }

    // MARK: - Scheduling

    func isScheduled(for date: Date) -> Bool {
        frequency.contains(habitWeekday(from: date))
    }

    // MARK: - Completion helpers

    func completedDaySet() -> Set<Date> {
        let cal = Calendar.current
        return Set(entries.map { cal.startOfDay(for: $0.date) })
    }

    func isCompleted(on date: Date, daySet: Set<Date>? = nil) -> Bool {
        let key = Calendar.current.startOfDay(for: date)
        if let set = daySet { return set.contains(key) }
        return entries.contains { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    // MARK: - Stats

    func completionRate(for days: Int = 30) -> Double {
        let cal       = Calendar.current
        let today     = cal.startOfDay(for: Date())
        let daySet    = completedDaySet()
        var scheduled = 0, completed = 0
        for i in 0..<days {
            guard let date = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            if isScheduled(for: date) {
                scheduled += 1
                if daySet.contains(date) { completed += 1 }
            }
        }
        return scheduled > 0 ? Double(completed) / Double(scheduled) : 0
    }

    var currentStreak: Int {
        let cal    = Calendar.current
        let daySet = completedDaySet()
        var date   = cal.startOfDay(for: Date())
        var streak = 0
        let cutoff = cal.startOfDay(for: createdAt)

        if isScheduled(for: date) && !daySet.contains(date) {
            guard let y = cal.date(byAdding: .day, value: -1, to: date) else { return 0 }
            date = y
        }
        for _ in 0..<365 {
            if date < cutoff { break }
            if isScheduled(for: date) {
                if daySet.contains(date) { streak += 1 } else { break }
            }
            guard let prev = cal.date(byAdding: .day, value: -1, to: date) else { break }
            date = prev
        }
        return streak
    }

    var longestStreak: Int {
        let cal     = Calendar.current
        let daySet  = completedDaySet()
        var date    = cal.startOfDay(for: createdAt)
        let today   = cal.startOfDay(for: Date())
        var longest = 0, current = 0
        while date <= today {
            if isScheduled(for: date) {
                if daySet.contains(date) { current += 1; longest = max(longest, current) }
                else { current = 0 }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return longest
    }

    func heatmapData() -> [(date: Date, completed: Bool, scheduled: Bool)] {
        let cal    = Calendar.current
        let today  = cal.startOfDay(for: Date())
        let daySet = completedDaySet()
        return (0..<126).reversed().compactMap { i -> (date: Date, completed: Bool, scheduled: Bool)? in
            guard let date = cal.date(byAdding: .day, value: -i, to: today) else { return nil }
            return (date: date, completed: daySet.contains(date), scheduled: isScheduled(for: date))
        }
    }
}

// MARK: - HabitEntry

@Model
final class HabitEntry {
    var id: UUID
    var date: Date
    var note: String
    var habit: Habit?

    init(date: Date = Date(), note: String = "", habit: Habit? = nil) {
        self.id    = UUID()
        self.date  = date
        self.note  = note
        self.habit = habit
    }
}

// MARK: - Color helpers

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >>  8) & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }

    func toHex() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }
}
