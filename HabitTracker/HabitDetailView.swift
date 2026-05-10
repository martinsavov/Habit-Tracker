import SwiftUI
import SwiftData

struct HabitDetailView: View {
    let habit: Habit
    @State private var showingEdit = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HeaderCard(habit: habit)        .padding(.horizontal)
                StatsRowView(habit: habit)      .padding(.horizontal)
                HeatmapView(habit: habit)       .padding(.horizontal)
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

    // Mon=0 … Sun=6
    private var frequencyLabel: String {
        let days = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
        if habit.frequency.count == 7     { return "Every day" }
        if habit.frequency == [0,1,2,3,4] { return "Weekdays"  }
        if habit.frequency == [5,6]       { return "Weekends"  }
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
                     color: .blue)
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

// MARK: - Heatmap (Mon first)

struct HeatmapView: View {
    let habit: Habit

    private var data: [(date: Date, completed: Bool, scheduled: Bool)] {
        habit.heatmapData()
    }

    // Each column = one week, rows = Mon(0)…Sun(6)
    private var weeks: [[(date: Date, completed: Bool, scheduled: Bool)?]] {
        var result: [[(date: Date, completed: Bool, scheduled: Bool)?]] = []
        var week: [(date: Date, completed: Bool, scheduled: Bool)?] = Array(repeating: nil, count: 7)
        // habitWeekday gives Mon=0…Sun=6
        let firstDayIndex = data.first.map { habitWeekday(from: $0.date) } ?? 0
        var dayIndex = firstDayIndex

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

    // Use index-based IDs — Mon/Tue/etc are unique but let's be safe
    private struct RowLabel: Identifiable {
        let id: Int; let letter: String
    }
    private let rowLabels = ["M","T","W","T","F","S","S"]
        .enumerated().map { RowLabel(id: $0.offset, letter: $0.element) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity").font(.headline)

            HStack(alignment: .top, spacing: 4) {
                // Day-of-week labels Mon–Sun
                VStack(spacing: 0) {
                    ForEach(rowLabels) { rl in
                        Text(rl.letter)
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
