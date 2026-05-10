import SwiftUI
import SwiftData

struct AllHabitsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.sortOrder) private var habits: [Habit]
    @State private var showingAddHabit = false

    var body: some View {
        NavigationStack {
            Group {
                if habits.isEmpty {
                    EmptyStateView(showingAddHabit: $showingAddHabit)
                } else {
                    List {
                        ForEach(habits) { habit in
                            NavigationLink(destination: HabitDetailView(habit: habit)) {
                                HabitListRow(habit: habit)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        }
                        .onDelete(perform: deleteHabits)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("My Habits")
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

    private func deleteHabits(at offsets: IndexSet) {
        for index in offsets { context.delete(habits[index]) }
        do { try context.save() } catch { print("Delete error: \(error)") }
    }
}

// MARK: - Habit List Row

struct HabitListRow: View {
    let habit: Habit

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(habit.color.opacity(0.15))
                    .frame(width: 48, height: 48)
                Text(habit.emoji).font(.title2)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name)
                    .font(.body).fontWeight(.semibold)

                HStack(spacing: 12) {
                    Label("\(habit.currentStreak)d streak", systemImage: "flame.fill")
                        .font(.caption).foregroundStyle(.orange)
                    Label("\(Int(habit.completionRate() * 100))%", systemImage: "chart.bar.fill")
                        .font(.caption).foregroundStyle(.purple)
                }
            }

            Spacer()

            MiniWeekView(habit: habit)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Mini Week View
// FIX: use enumerated index as ID so duplicate day letters don't cause SwiftUI confusion

struct MiniWeekView: View {
    let habit: Habit

    // oldest → newest, last 7 days
    private var last7: [Date] {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(last7.enumerated()), id: \.offset) { _, date in
                let scheduled = habit.isScheduled(for: date)
                let completed = habit.isCompleted(on: date)
                Circle()
                    .fill(
                        completed  ? habit.color :
                        scheduled  ? habit.color.opacity(0.15) :
                        Color.clear
                    )
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle().stroke(
                            scheduled && !completed ? habit.color.opacity(0.3) : Color.clear,
                            lineWidth: 1
                        )
                    )
            }
        }
    }
}
