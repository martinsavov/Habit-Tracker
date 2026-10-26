import SwiftUI
import SwiftData
import UserNotifications

struct AllHabitsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.sortOrder) private var habits: [Habit]
    @State private var showingAddHabit = false
    @State private var isEditing = false
    @State private var expandedID: UUID?
    @State private var habitToEdit: Habit?

    var body: some View {
        NavigationStack {
            Group {
                if habits.isEmpty {
                    EmptyStateView(showingAddHabit: $showingAddHabit)
                } else {
                    List {
                        ForEach(habits) { habit in
                            HabitAccordionCard(
                                habit: habit,
                                isExpanded: expandedID == habit.id && !isEditing,
                                onToggle: { toggle(habit) },
                                onEdit:   { habitToEdit = habit }
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        }
                        .onDelete(perform: deleteHabits)
                        .onMove(perform: moveHabits)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, .constant(isEditing ? .active : .inactive))
                }
            }
            .navigationTitle("My Habits")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !habits.isEmpty {
                        Button(isEditing ? "Done" : "Reorder") {
                            withAnimation { isEditing.toggle() }
                        }
                        .foregroundStyle(.blue)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddHabit = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .sheet(isPresented: $showingAddHabit) {
                AddEditHabitView()
            }
            .sheet(item: $habitToEdit) { habit in
                AddEditHabitView(habit: habit)
            }
        }
    }

    private func toggle(_ habit: Habit) {
        withAnimation(.snappy(duration: 0.3)) {
            expandedID = (expandedID == habit.id) ? nil : habit.id
        }
    }

    private func deleteHabits(at offsets: IndexSet) {
        let ids = offsets.map { habits[$0].id.uuidString }
        cancelHabitNotifications(ids: ids)
        for index in offsets { context.delete(habits[index]) }
        do { try context.save() } catch { print("Delete error: \(error)") }
    }

    private func moveHabits(from source: IndexSet, to destination: Int) {
        var reordered = habits
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, habit) in reordered.enumerated() {
            habit.sortOrder = index
        }
        do { try context.save() } catch { print("Move error: \(error)") }
    }
}

// MARK: - Accordion card
// Collapsed: icon, name, streak, last 7 days. Expanded: stats + month calendar.

struct HabitAccordionCard: View {
    let habit: Habit
    let isExpanded: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void

    @State private var monthOffset = 0   // 0 = this month, -1 = last month …

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) { header }
                .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    Divider().padding(.horizontal, 14)
                    statsRow
                    HabitMonthCalendar(habit: habit, monthOffset: $monthOffset)
                        .padding(.horizontal, 14)
                        .padding(.top, 6)
                    Divider().padding(.horizontal, 14).padding(.top, 8)
                    footer
                }
                .transition(.opacity)
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            HabitIconTile(icon: habit.emoji, color: habit.color, side: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(.body).fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if !isExpanded {
                MiniWeekView(habit: habit)
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let streak = "\(habit.currentStreak) day streak"
        return isExpanded ? "\(streak) · \(frequencyLabel)" : streak
    }

    // Mon=0 … Sun=6
    private var frequencyLabel: String {
        let days = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
        let f = habit.frequency.sorted()
        if f.count == 7     { return "Every day" }
        if f == [0,1,2,3,4] { return "Weekdays"  }
        if f == [5,6]       { return "Weekends"  }
        return f.map { days[$0] }.joined(separator: ", ")
    }

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: 0) {
            statColumn(value: "\(habit.currentStreak)", label: "Current")
            Divider().frame(height: 30)
            statColumn(value: "\(habit.longestStreak)", label: "Best")
            Divider().frame(height: 30)
            statColumn(value: "\(Int(habit.completionRate() * 100))%", label: "30 days")
        }
        .padding(.vertical, 14)
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3).fontWeight(.bold)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Edit habit", action: onEdit)
                .font(.body)
            Spacer()
            if habit.reminderEnabled, let time = habit.reminderTime {
                Text("Reminder \(time.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
    }
}

// MARK: - Mini Week View (last 7 days)
// Uses the enumerated index as ID so repeated values never confuse SwiftUI.

struct MiniWeekView: View {
    let habit: Habit

    // oldest → newest, last 7 days
    private var last7: [Date] {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(last7.enumerated()), id: \.offset) { _, date in
                let scheduled = habit.isScheduled(for: date)
                let completed = habit.isCompleted(on: date)
                Circle()
                    .fill(
                        completed ? habit.color :
                        scheduled ? habit.color.opacity(0.15) :
                        Color.clear
                    )
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle().stroke(
                            scheduled && !completed ? habit.color.opacity(0.4) : Color.clear,
                            lineWidth: 1
                        )
                    )
            }
        }
        .accessibilityHidden(true)
    }
}
