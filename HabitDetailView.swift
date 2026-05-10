import SwiftUI
import SwiftData

struct HabitDetailView: View {
    let habit: Habit
    @State private var showingEdit = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HeaderCard(habit: habit)       .padding(.horizontal)
                StatsRowView(habit: habit)     .padding(.horizontal)
                HeatmapView(habit: habit)      .padding(.horizontal)
                CompletionRateCard(habit: habit).padding(.horizontal)
            }
            .padding(.bottom, 32)
        }
        .navigationTitle(habit.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddEditHabitView(habit: habit)
        }
    }
}

// MARK: - Header Card

struct HeaderCard: View {
    let habit: Habit

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(habit.color.opacity(0.15))
                    .frame(width: 64, height: 64)
                Text(habit.emoji).font(.largeTitle)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name).font(.title2).fontWeight(.bold)
                Text(frequencyLabel).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var frequencyLabel: String {
        let days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
        if habit.frequency.count == 7     { return "Every day" }
        if habit.frequency == [1,2,3,4,5] { return "Weekdays"  }
        if habit.frequency == [0,6]       { return "Weekends"  }
        return habit.frequency.map { days[$0] }.joined(separator: ", ")
    }
}

// MARK: - Stats Row

struct StatsRowView: View {
    let habit: Habit

    var body: some View {
        HStack(spacing: 12) {
            StatCard(value: "\(habit.currentStreak)",
                     label: "Current\nStreak",
                     icon:  "flame.fill",
                     color: .orange)
            StatCard(value: "\(habit.longestStreak)",
                     label: "Longest\nStreak",
                     icon:  "trophy.fill",
                     color: .yellow)
            StatCard(value: "\(Int(habit.completionRate() * 100))%",
                     label: "30-Day\nRate",
                     icon:  "chart.bar.fill",
                     color: .purple)
        }
    }
}

struct StatCard: View {
    let value: String
    let label: String
    let icon:  String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(value).font(.title2).fontWeight(.bold)
            Text(label)
                .font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Heatmap
// FIX: day-label ForEach used duplicate string IDs ("T" x2, "S" x3).
//      Use enumerated offset as the identity instead.

struct HeatmapView: View {
    let habit: Habit

    private var data: [(date: Date, completed: Bool, scheduled: Bool)] {
        habit.heatmapData()
    }

    // Arrange data into columns of 7 rows (Sun–Sat)
    private var weeks: [[(date: Date, completed: Bool, scheduled: Bool)?]] {
        var result: [[(date: Date, completed: Bool, scheduled: Bool)?]] = []
        var week: [(date: Date, completed: Bool, scheduled: Bool)?] = Array(repeating: nil, count: 7)
        let firstWeekday = Calendar.current.component(.weekday, from: data.first?.date ?? Date()) - 1
        var dayIndex = firstWeekday

        for item in data {
            week[dayIndex] = item
            dayIndex += 1
            if dayIndex == 7 {
                result.append(week)
                week = Array(repeating: nil, count: 7)
                dayIndex = 0
            }
        }
        if dayIndex > 0 { result.append(week) }
        return result
    }

    // Named struct so ForEach can use a stable ID
    private struct DayLabel: Identifiable {
        let id: Int
        let letter: String
    }
    private let dayLabels = ["S","M","T","W","T","F","S"]
        .enumerated().map { DayLabel(id: $0.offset, letter: $0.element) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity").font(.headline)

            HStack(alignment: .top, spacing: 4) {
                // Day-of-week labels — use index-based identity to avoid duplicate-string crash
                VStack(spacing: 0) {
                    ForEach(dayLabels) { dl in
                        Text(dl.letter)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(width: 12, height: 14)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(weeks.indices, id: \.self) { wi in
                            VStack(spacing: 4) {
                                ForEach(0..<7, id: \.self) { di in
                                    if let item = weeks[wi][di] {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(
                                                item.completed ? habit.color :
                                                item.scheduled ? habit.color.opacity(0.12) :
                                                Color.clear
                                            )
                                            .frame(width: 12, height: 12)
                                    } else {
                                        Color.clear.frame(width: 12, height: 12)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 16) {
                Spacer()
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(habit.color.opacity(0.12))
                        .frame(width: 10, height: 10)
                    Text("Scheduled").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(habit.color)
                        .frame(width: 10, height: 10)
                    Text("Done").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Completion Rate Card

struct CompletionRateCard: View {
    let habit: Habit

    private var last30: [(date: Date, completed: Bool)] {
        let cal    = Calendar.current
        let today  = cal.startOfDay(for: Date())
        let daySet = habit.completedDaySet()
        return (0..<30).compactMap { i -> (date: Date, completed: Bool)? in
            guard let d = cal.date(byAdding: .day, value: -i, to: today),
                  habit.isScheduled(for: d) else { return nil }
            return (date: d, completed: daySet.contains(d))
        }.reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 30 Days").font(.headline)

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(last30.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(last30[i].completed ? habit.color : habit.color.opacity(0.15))
                        .frame(maxWidth: .infinity,
                               minHeight: 4,
                               maxHeight: last30[i].completed ? 40 : 14)
                }
            }
            .frame(height: 44)

            HStack {
                Text("\(last30.filter { $0.completed }.count) of \(last30.count) completed")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(habit.completionRate(for: 30) * 100))%")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(habit.color)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
