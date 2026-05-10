import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.sortOrder) private var habits: [Habit]
    @State private var showingAddHabit = false
    // Use startOfDay so all date comparisons are on midnight-aligned values
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())

    private var todayHabits: [Habit] {
        habits.filter { $0.isScheduled(for: selectedDate) }
    }

    private var completedCount: Int {
        todayHabits.filter { $0.isCompleted(on: selectedDate) }.count
    }

    private var progress: Double {
        guard !todayHabits.isEmpty else { return 0 }
        return Double(completedCount) / Double(todayHabits.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    DateStripView(selectedDate: $selectedDate)

                    ProgressRingView(
                        progress:  progress,
                        completed: completedCount,
                        total:     todayHabits.count
                    )
                    .padding(.horizontal)

                    if todayHabits.isEmpty {
                        EmptyStateView(showingAddHabit: $showingAddHabit)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(todayHabits) { habit in
                                HabitRowView(habit: habit, date: selectedDate)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 32)
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddHabit = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.purple)
                    }
                }
            }
            .sheet(isPresented: $showingAddHabit) {
                AddEditHabitView()
            }
        }
    }

    private var navTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDate)      { return "Today" }
        if cal.isDateInYesterday(selectedDate)  { return "Yesterday" }
        return selectedDate.formatted(.dateTime.weekday(.wide))
    }
}

// MARK: - Date Strip

struct DateStripView: View {
    @Binding var selectedDate: Date

    private var days: [Date] {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (-6...0).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days, id: \.self) { date in
                    DayChip(
                        date:       date,
                        isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate)
                    )
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.2)) { selectedDate = date }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct DayChip: View {
    let date: Date
    let isSelected: Bool

    private var dayLetter: String { date.formatted(.dateTime.weekday(.narrow)) }
    private var dayNumber: String  { date.formatted(.dateTime.day()) }
    private var isToday: Bool      { Calendar.current.isDateInToday(date) }

    var body: some View {
        VStack(spacing: 4) {
            Text(dayLetter)
                .font(.caption2).fontWeight(.semibold)
                .foregroundStyle(isSelected ? .white : .secondary)
            Text(dayNumber)
                .font(.callout).fontWeight(.bold)
                .foregroundStyle(isSelected ? .white : (isToday ? .purple : .primary))
        }
        .frame(width: 44, height: 60)
        .background(isSelected ? Color.purple : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isToday && !isSelected ? Color.purple.opacity(0.4) : .clear, lineWidth: 1.5)
        )
    }
}

// MARK: - Progress Ring

struct ProgressRingView: View {
    let progress:  Double
    let completed: Int
    let total:     Int

    @State private var animated: Double = 0

    var body: some View {
        HStack(spacing: 28) {
            ZStack {
                Circle()
                    .stroke(Color.purple.opacity(0.12), lineWidth: 14)

                Circle()
                    .trim(from: 0, to: animated)
                    .stroke(
                        LinearGradient(colors: [.purple, .pink],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(duration: 0.7), value: animated)

                VStack(spacing: 2) {
                    Text("\(Int(animated * 100))%")
                        .font(.title2).fontWeight(.bold)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.5), value: animated)
                    Text("done")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 110, height: 110)
            .onAppear { animated = progress }
            .onChange(of: progress) { _, newValue in animated = newValue }

            VStack(alignment: .leading, spacing: 10) {
                StatRow(label: "Completed", value: "\(completed) / \(total)", color: .purple)
                StatRow(label: "Remaining", value: "\(max(0, total - completed))", color: .orange)
                StatRow(label: "Rate",
                        value: total > 0 ? "\(Int(progress * 100))%" : "—",
                        color: .green)
            }
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct StatRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption).fontWeight(.semibold)
        }
    }
}

// MARK: - Habit Row

struct HabitRowView: View {
    @Environment(\.modelContext) private var context
    let habit: Habit
    let date:  Date

    @State private var bouncing = false

    private var isCompleted: Bool { habit.isCompleted(on: date) }

    var body: some View {
        HStack(spacing: 14) {
            // Emoji badge
            ZStack {
                Circle()
                    .fill(habit.color.opacity(0.15))
                    .frame(width: 50, height: 50)
                Text(habit.emoji).font(.title2)
            }

            // Name + streak
            VStack(alignment: .leading, spacing: 3) {
                Text(habit.name)
                    .font(.body).fontWeight(.semibold)
                    .strikethrough(isCompleted, color: .secondary)
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                    .animation(.easeInOut(duration: 0.2), value: isCompleted)

                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.caption2).foregroundStyle(.orange)
                    Text(streakLabel)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Check button
            Button { toggleCompletion() } label: {
                ZStack {
                    Circle()
                        .fill(isCompleted ? habit.color : Color(.tertiarySystemBackground))
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(
                            isCompleted ? habit.color : Color.secondary.opacity(0.3),
                            lineWidth: 2
                        ))
                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.caption).fontWeight(.bold)
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .scaleEffect(bouncing ? 1.25 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: bouncing)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .animation(.easeInOut(duration: 0.15), value: isCompleted)
    }

    private var streakLabel: String {
        let s = habit.currentStreak
        return s == 1 ? "1 day streak" : "\(s) day streak"
    }

    private func toggleCompletion() {
        let cal = Calendar.current
        if isCompleted {
            if let entry = habit.entries.first(where: { cal.isDate($0.date, inSameDayAs: date) }) {
                context.delete(entry)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } else {
            let entry = HabitEntry(date: date, habit: habit)
            context.insert(entry)
            bouncing = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { bouncing = false }
        }
        do { try context.save() } catch { print("Save error: \(error)") }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    @Binding var showingAddHabit: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 52))
                .foregroundStyle(.purple.opacity(0.5))
            Text("No habits today")
                .font(.title3).fontWeight(.semibold)
            Text("Add a habit to start building your streak")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add Habit") { showingAddHabit = true }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
        }
        .padding(40)
    }
}
