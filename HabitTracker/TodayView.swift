import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Habit.sortOrder) private var habits: [Habit]
    @State private var showingAddHabit = false
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var todayDate = Calendar.current.startOfDay(for: Date())

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
                            .foregroundStyle(.blue)
                    }
                }
            }
            .sheet(isPresented: $showingAddHabit) {
                AddEditHabitView()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    let newToday = Calendar.current.startOfDay(for: Date())
                    if newToday != todayDate {
                        todayDate    = newToday
                        selectedDate = newToday
                    }
                }
            }
        }
    }

    private var navTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDate)     { return "Today" }
        if cal.isDateInYesterday(selectedDate) { return "Yesterday" }
        return selectedDate.formatted(.dateTime.weekday(.wide))
    }
}

// MARK: - Date Strip (Mon first)

struct DateStripView: View {
    @Binding var selectedDate: Date

    // Last 7 days oldest→newest, always Mon-aligned display
    private var days: [Date] {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (-6...0).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { date in
                        DayChip(
                            date:       date,
                            isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate)
                        )
                        .id(date)
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.2)) { selectedDate = date }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }
                .padding(.horizontal)
            }
            .onAppear {
                if let today = days.last {
                    proxy.scrollTo(today, anchor: .trailing)
                }
            }
        }
    }
}

struct DayChip: View {
    let date: Date
    let isSelected: Bool

    private var dayLabel: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }
    private var dayNumber: String { date.formatted(.dateTime.day()) }
    private var isToday: Bool     { Calendar.current.isDateInToday(date) }

    var body: some View {
        VStack(spacing: 4) {
            Text(dayLabel)
                .font(.caption2).fontWeight(.semibold)
                .foregroundStyle(isSelected ? .white : .secondary)
            Text(dayNumber)
                .font(.callout).fontWeight(.bold)
                .foregroundStyle(isSelected ? .white : (isToday ? .blue : .primary))
        }
        .frame(width: 52, height: 60)
        .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isToday && !isSelected ? Color.blue.opacity(0.4) : .clear, lineWidth: 1.5)
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
                    .stroke(Color.blue.opacity(0.12), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: animated)
                    .stroke(
                        LinearGradient(colors: [.blue, Color(hex: "#00C6FF") ?? .cyan],
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
                StatRow(label: "Completed", value: "\(completed) / \(total)", color: .blue)
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
    @State private var showingNoteSheet = false
    @State private var pendingEntry: HabitEntry? = nil

    private var isCompleted: Bool { habit.isCompleted(on: date) }

    private var existingEntry: HabitEntry? {
        let cal = Calendar.current
        return habit.entries.first(where: { cal.isDate($0.date, inSameDayAs: date) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(habit.color.opacity(0.15))
                        .frame(width: 50, height: 50)
                    Text(habit.emoji).font(.title2)
                }

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

                // Note indicator
                if let entry = existingEntry, let note = entry.note, !note.isEmpty {
                    Button {
                        showingNoteSheet = true
                    } label: {
                        Image(systemName: "note.text")
                            .font(.caption)
                            .foregroundStyle(habit.color)
                    }
                    .buttonStyle(.plain)
                }

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

            // Show note if exists
            if let entry = existingEntry, let note = entry.note, !note.isEmpty {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(habit.color)
                        .frame(width: 2)
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.leading, 64)
                .padding(.top, 6)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .animation(.easeInOut(duration: 0.15), value: isCompleted)
        .sheet(isPresented: $showingNoteSheet) {
            if let entry = existingEntry ?? pendingEntry {
                HabitNoteSheet(entry: entry, habitColor: habit.color)
            }
        }
    }

    private var streakLabel: String {
        let s = habit.currentStreak
        return s == 1 ? "1 day streak" : "\(s) day streak"
    }

    private func toggleCompletion() {
        let cal = Calendar.current
        if isCompleted {
            if let entry = existingEntry {
                context.delete(entry)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } else {
            let entry = HabitEntry(date: date, note: nil, habit: habit)
            context.insert(entry)
            do { try context.save() } catch { print("Save error: \(error)") }
            pendingEntry = entry
            bouncing = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { bouncing = false }
            // Show note sheet after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showingNoteSheet = true
            }
            return
        }
        do { try context.save() } catch { print("Save error: \(error)") }
    }
}

// MARK: - Habit Note Sheet

struct HabitNoteSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let entry: HabitEntry
    let habitColor: Color

    @State private var note: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("How did it go?")
                    .font(.headline)
                    .padding(.horizontal)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                    if note.isEmpty {
                        Text("Add a note... (optional)")
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                    TextEditor(text: $note)
                        .padding(8)
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                }
                .frame(height: 120)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        entry.note = note.isEmpty ? nil : note
                        do { try context.save() } catch { print("Note save error: \(error)") }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            note = entry.note ?? ""
            focused = true
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    @Binding var showingAddHabit: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 52))
                .foregroundStyle(.blue.opacity(0.5))
            Text("No habits today")
                .font(.title3).fontWeight(.semibold)
            Text("Add a habit to start building your streak")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add Habit") { showingAddHabit = true }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
        }
        .padding(40)
    }
}
