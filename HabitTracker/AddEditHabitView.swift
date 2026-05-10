import SwiftUI
import SwiftData
import UserNotifications

// Top-level so DayToggleButton can reference it without access issues
struct DayItem: Identifiable {
    let id: Int        // 0=Mon … 6=Sun
    let label: String  // "Mon", "Tue" …
}

let allDayItems: [DayItem] = [
    DayItem(id: 0, label: "Mon"),
    DayItem(id: 1, label: "Tue"),
    DayItem(id: 2, label: "Wed"),
    DayItem(id: 3, label: "Thu"),
    DayItem(id: 4, label: "Fri"),
    DayItem(id: 5, label: "Sat"),
    DayItem(id: 6, label: "Sun"),
]

struct AddEditHabitView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Habit.sortOrder) private var allHabits: [Habit]

    var habit: Habit? = nil

    @State private var name            = ""
    @State private var emoji           = "⭐"
    @State private var selectedColor   = "#0A84FF"
    @State private var frequency: Set<Int> = [0,1,2,3,4,5,6]
    @State private var reminderEnabled = false
    @State private var reminderTime    = Calendar.current.date(
        bySettingHour: 9, minute: 0, second: 0, of: Date()
    ) ?? Date()
    @State private var showingEmojiPicker = false

    private let palette: [String] = [
        "#0A84FF", "#30D158", "#FF9F0A", "#FF453A",
        "#BF5AF2", "#FF375F", "#40CBE0", "#FFD60A",
        "#5E5CE6", "#FF6B6B", "#4ECDC4", "#F0B27A"
    ]

    var body: some View {
        NavigationStack {
            Form {

                // ── Name & Emoji ──────────────────────────────────────────
                Section {
                    HStack(spacing: 16) {
                        Button { showingEmojiPicker = true } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill((Color(hex: selectedColor) ?? .blue).opacity(0.2))
                                    .frame(width: 56, height: 56)
                                Text(emoji).font(.largeTitle)
                            }
                        }
                        .buttonStyle(.plain)

                        TextField("Habit name", text: $name)
                            .font(.body)
                            .submitLabel(.done)
                    }
                    .padding(.vertical, 4)
                }

                // ── Color ─────────────────────────────────────────────────
                Section("Color") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 6),
                        spacing: 12
                    ) {
                        ForEach(palette, id: \.self) { hex in
                            let isSelected = selectedColor == hex
                            Circle()
                                .fill(Color(hex: hex) ?? .blue)
                                .frame(width: 36, height: 36)
                                .overlay(Circle().stroke(.white, lineWidth: isSelected ? 3 : 0))
                                .overlay(
                                    Circle()
                                        .stroke(Color(hex: hex) ?? .blue, lineWidth: isSelected ? 1 : 0)
                                        .padding(-3)
                                )
                                .scaleEffect(isSelected ? 1.1 : 1.0)
                                .animation(.spring(duration: 0.2), value: isSelected)
                                .onTapGesture {
                                    selectedColor = hex
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // ── Frequency Mon–Sun ─────────────────────────────────────
                Section("Repeat") {
                    VStack(spacing: 8) {
                        // Row 1: Mon–Fri
                        HStack(spacing: 6) {
                            ForEach(allDayItems.prefix(5)) { item in
                                DayToggleButton(
                                    item:     item,
                                    selected: frequency.contains(item.id),
                                    color:    Color(hex: selectedColor) ?? .blue
                                ) { toggleDay(item.id) }
                            }
                        }
                        // Row 2: Sat–Sun (left-aligned)
                        HStack(spacing: 6) {
                            ForEach(allDayItems.suffix(2)) { item in
                                DayToggleButton(
                                    item:     item,
                                    selected: frequency.contains(item.id),
                                    color:    Color(hex: selectedColor) ?? .blue
                                ) { toggleDay(item.id) }
                            }
                            Spacer()
                        }
                    }

                    HStack(spacing: 8) {
                        QuickSelectButton(label: "Every day") { frequency = Set(0...6)   }
                        QuickSelectButton(label: "Weekdays")  { frequency = [0,1,2,3,4] }
                        QuickSelectButton(label: "Weekends")  { frequency = [5,6]        }
                    }
                }

                // ── Reminder ──────────────────────────────────────────────
                Section("Reminder") {
                    Toggle("Daily Reminder", isOn: $reminderEnabled.animation())
                        .tint(Color(hex: selectedColor) ?? .blue)
                    if reminderEnabled {
                        DatePicker("Time",
                                   selection: $reminderTime,
                                   displayedComponents: .hourAndMinute)
                    }
                }

                // ── Delete (edit mode only) ───────────────────────────────
                if habit != nil {
                    Section {
                        Button(role: .destructive) { deleteHabit() } label: {
                            Label("Delete Habit", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(habit == nil ? "New Habit" : "Edit Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingEmojiPicker) {
                EmojiPickerView(selectedEmoji: $emoji)
            }
        }
        .onAppear { populateFields() }
    }

    // MARK: - Helpers

    private func toggleDay(_ id: Int) {
        if frequency.contains(id) && frequency.count > 1 {
            frequency.remove(id)
        } else {
            frequency.insert(id)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func populateFields() {
        guard let h = habit else { return }
        name            = h.name
        emoji           = h.emoji
        selectedColor   = h.colorHex
        frequency       = Set(h.frequency)
        reminderEnabled = h.reminderEnabled
        reminderTime    = h.reminderTime ?? reminderTime
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if let h = habit {
            cancelNotification(id: h.id.uuidString)
            h.name            = trimmed
            h.emoji           = emoji
            h.colorHex        = selectedColor
            h.frequency       = Array(frequency).sorted()
            h.reminderEnabled = reminderEnabled
            h.reminderTime    = reminderEnabled ? reminderTime : nil
            if reminderEnabled { scheduleNotification(id: h.id.uuidString, habitName: trimmed) }
        } else {
            let h = Habit(
                name:            trimmed,
                emoji:           emoji,
                colorHex:        selectedColor,
                frequency:       Array(frequency).sorted(),
                reminderTime:    reminderEnabled ? reminderTime : nil,
                reminderEnabled: reminderEnabled,
                sortOrder:       allHabits.count
            )
            context.insert(h)
            do { try context.save() } catch { print("Insert error: \(error)"); return }
            if reminderEnabled { scheduleNotification(id: h.id.uuidString, habitName: trimmed) }
        }

        do { try context.save() } catch { print("Save error: \(error)") }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func deleteHabit() {
        guard let h = habit else { return }
        cancelNotification(id: h.id.uuidString)
        context.delete(h)
        do { try context.save() } catch { print("Delete error: \(error)") }
        dismiss()
    }

    private func cancelNotification(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    private func scheduleNotification(id: String, habitName: String) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                guard granted else { return }
                let content   = UNMutableNotificationContent()
                content.title = habitName
                content.body  = "Time to build your streak 🔥"
                content.sound = .default
                let comps     = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                let trigger   = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let req       = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(req) { err in
                    if let err { print("Notification error: \(err)") }
                }
            }
    }
}

// MARK: - Day Toggle Button

struct DayToggleButton: View {
    let item:     DayItem
    let selected: Bool
    let color:    Color
    let onTap:    () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(item.label)
                .font(.caption).fontWeight(.semibold)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(selected ? color : Color(.tertiarySystemBackground))
                .foregroundStyle(selected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .animation(.spring(duration: 0.2), value: selected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick Select Button

struct QuickSelectButton: View {
    let label:  String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Emoji Picker

struct EmojiPickerView: View {
    @Binding var selectedEmoji: String
    @Environment(\.dismiss) private var dismiss

    private let emojis: [String] = [
        "⭐","🔥","💪","🏃","📚","🎯","💧","🥗","😴","🧘",
        "✍️","🎨","🎵","🚴","🏊","🧗","🌿","🍎","☀️","🌙",
        "💊","🧠","❤️","🤸","🍵","📝","🗣️","🚶","🏋️","🎉",
        "💰","🌍","🦷","🛁","🧹","📱","💻","✉️","🎮","🧩",
        "🏆","⚡","🌊","🎭","🦋","🌸","🍕","☕","🎸","🏅"
    ]
    private let columns = Array(repeating: GridItem(.flexible()), count: 8)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(emojis, id: \.self) { e in
                        Button {
                            selectedEmoji = e
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            dismiss()
                        } label: {
                            Text(e).font(.largeTitle)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
