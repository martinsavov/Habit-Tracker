import SwiftUI

// MARK: - Habit icon storage
//
// Habit.emoji is a plain String in the database. To avoid any schema change,
// new icons are stored in that same field with an "sf:" prefix, e.g.
// "sf:figure.run". Anything without the prefix is a legacy emoji and is
// still drawn as text, so existing habits keep working untouched.

enum HabitIcon {
    static let prefix = "sf:"
    static let defaultValue = "sf:star.fill"

    // SF Symbol names offered in the picker (all available on iOS 17).
    static let all: [String] = [
        "star.fill", "flame.fill", "figure.run", "dumbbell.fill", "book.fill",
        "target", "drop.fill", "leaf.fill", "moon.fill", "figure.mind.and.body",
        "pencil", "paintpalette.fill", "music.note", "bicycle", "figure.pool.swim",
        "figure.climbing", "carrot.fill", "fork.knife", "sun.max.fill", "pills.fill",
        "brain.head.profile", "heart.fill", "figure.walk", "cup.and.saucer.fill", "doc.text.fill",
        "bubble.left.fill", "banknote.fill", "globe.europe.africa.fill", "shower.fill", "sparkles",
        "iphone", "laptopcomputer", "envelope.fill", "gamecontroller.fill", "puzzlepiece.fill",
        "trophy.fill", "bolt.fill", "bed.double.fill", "figure.yoga", "alarm.fill",
        "camera.fill", "cart.fill", "house.fill", "pawprint.fill", "mouth.fill"
    ]

    static func value(forSymbol symbol: String) -> String { prefix + symbol }

    /// SF Symbol to draw for a stored value: the new "sf:" form, or the closest
    /// symbol for an old emoji (display only, the stored value is never changed).
    static func symbolName(from value: String) -> String? {
        if value.hasPrefix(prefix) { return String(value.dropFirst(prefix.count)) }
        return legacyEmojiMap[value]
    }

    // Closest symbol for every emoji the old picker offered.
    private static let legacyEmojiMap: [String: String] = [
        "⭐": "star.fill", "🔥": "flame.fill", "💪": "dumbbell.fill", "🏃": "figure.run",
        "📚": "book.fill", "🎯": "target", "💧": "drop.fill", "🥗": "fork.knife",
        "😴": "bed.double.fill", "🧘": "figure.yoga", "✍️": "pencil", "🎨": "paintpalette.fill",
        "🎵": "music.note", "🚴": "bicycle", "🏊": "figure.pool.swim", "🧗": "figure.climbing",
        "🌿": "leaf.fill", "🍎": "carrot.fill", "☀️": "sun.max.fill", "🌙": "moon.fill",
        "💊": "pills.fill", "🧠": "brain.head.profile", "❤️": "heart.fill", "🤸": "figure.mind.and.body",
        "🍵": "cup.and.saucer.fill", "📝": "doc.text.fill", "🗣️": "bubble.left.fill", "🚶": "figure.walk",
        "🏋️": "dumbbell.fill", "🎉": "sparkles", "💰": "banknote.fill", "🌍": "globe.europe.africa.fill",
        "🦷": "mouth.fill", "🛁": "shower.fill", "🧹": "house.fill", "📱": "iphone",
        "💻": "laptopcomputer", "✉️": "envelope.fill", "🎮": "gamecontroller.fill", "🧩": "puzzlepiece.fill",
        "🏆": "trophy.fill", "⚡": "bolt.fill", "🌊": "drop.fill", "🎭": "sparkles",
        "🦋": "sparkles", "🌸": "leaf.fill", "🍕": "fork.knife", "☕": "cup.and.saucer.fill",
        "🎸": "music.note", "🏅": "trophy.fill"
    ]
}

// MARK: - Icon drawing

/// Draws an SF Symbol. Old emojis are mapped to a symbol; an unknown one is shown as text.
struct HabitIconView: View {
    let value: String
    var size: CGFloat = 24

    var body: some View {
        if let name = HabitIcon.symbolName(from: value) {
            Image(systemName: name)
                .font(.system(size: size, weight: .medium))
        } else {
            Text(value).font(.system(size: size))
        }
    }
}

/// Rounded tile with the habit's colour tint behind its icon.
struct HabitIconTile: View {
    let icon: String
    let color: Color
    var side: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.29, style: .continuous)
                .fill(color.opacity(0.15))
            HabitIconView(value: icon, size: side * 0.48)
                .foregroundStyle(color)
        }
        .frame(width: side, height: side)
    }
}

// MARK: - Icon picker

struct IconPickerView: View {
    @Binding var selection: String
    let color: Color
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(HabitIcon.all, id: \.self) { symbol in
                        let value = HabitIcon.value(forSymbol: symbol)
                        let isSelected = selection == value
                        Button {
                            selection = value
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            dismiss()
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(isSelected ? Color.white : color)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(isSelected ? color : color.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
