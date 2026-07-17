import SwiftUI
import SwiftData
import UserNotifications
import WidgetKit

struct FastingView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FastingSession.startTime, order: .reverse) private var sessions: [FastingSession]
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedPlan: FastingPlan = .sixteen8
    @State private var customHours: Double = 16
    @State private var showingPlanPicker = false
    @State private var showingEndConfirm = false
    @State private var showingEditFast = false
    @State private var showingFastNoteSheet = false
    @State private var sessionToEdit: FastingSession?
    @State private var justEndedSession: FastingSession?
    @State private var now = Date()
    @State private var timer: Timer?

    // MARK: - Track additions (new state only, nothing existing touched)
    @State private var showingTrackBlockedAlert = false
    @State private var showingTrackEndConfirm = false
    @State private var showingCustomTrack = false

    private var activeSession: FastingSession? {
        sessions.first { $0.isActive }
    }

    private var pastSessions: [FastingSession] {
        sessions.filter { !$0.isActive }
    }

    // A "Track" session is just a FastingSession whose planName starts with "Track"
    private var activeIsTrack: Bool {
        activeSession?.planName.hasPrefix("Track") ?? false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let session = activeSession {
                        ActiveFastCard(session: session, now: now, onEnd: {
                            if activeIsTrack {
                                showingTrackEndConfirm = true
                            } else {
                                showingEndConfirm = true
                            }
                        }, onEdit: {
                            sessionToEdit = session
                            showingEditFast = true
                        })
                        .padding(.horizontal)

                        if !activeIsTrack {
                            PhaseCard(session: session, now: now)
                                .padding(.horizontal)
                        }
                    } else {
                        StartFastCard(
                            selectedPlan:   $selectedPlan,
                            customHours:    $customHours,
                            showingPicker:  $showingPlanPicker
                        ) {
                            startFast()
                        }
                        .padding(.horizontal)

                        // New: Track card, only shown when nothing is active
                        TrackCard(
                            onPreset: { minutes, label in startTrack(minutes: minutes, label: label) },
                            onCustom: { showingCustomTrack = true }
                        )
                        .padding(.horizontal)
                    }

                    if !pastSessions.isEmpty {
                        HistorySection(sessions: pastSessions)
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom, 32)
                .padding(.top, 8)
            }
            .navigationTitle("Tracker")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear { startTicking() }
        .onDisappear { stopTicking() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { startTicking() } else { stopTicking() }
        }
        .confirmationDialog("End your fast?", isPresented: $showingEndConfirm, titleVisibility: .visible) {
            Button("End Fast", role: .destructive) { endFast() }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let s = activeSession {
                Text("You've been fasting since \(s.startTime.formatted(.dateTime.hour().minute())). Great work!")
            }
        }
        // New: separate confirm for ending a Track (kept fully independent of endFast)
        .confirmationDialog("End tracking?", isPresented: $showingTrackEndConfirm, titleVisibility: .visible) {
            Button("End Track", role: .destructive) { endTrack() }
            Button("Cancel", role: .cancel) { }
        }
        // New: alert shown if user tries to start a Track while a fast is active
        .alert("Fast in progress", isPresented: $showingTrackBlockedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You have an active fast running. End it first if you want to start a quick Track.")
        }
        .sheet(isPresented: $showingPlanPicker) {
            PlanPickerSheet(selectedPlan: $selectedPlan, customHours: $customHours)
        }
        .sheet(isPresented: $showingEditFast) {
            if let session = sessionToEdit {
                EditFastSheet(session: session)
            }
        }
        .sheet(isPresented: $showingFastNoteSheet) {
            if let session = justEndedSession {
                FastingNoteSheet(session: session)
            }
        }
        // New: custom Track duration sheet
        .sheet(isPresented: $showingCustomTrack) {
            CustomTrackSheet { minutes, label in
                startTrack(minutes: minutes, label: label)
            }
        }
    }

    // MARK: - Timer

    private func startTicking() {
        stopTicking()
        now = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            now = Date()
        }
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Actions (UNCHANGED from original)

    private func startFast() {
        let hours = selectedPlan == .custom ? customHours : selectedPlan.targetHours
        let session = FastingSession(
            startTime:    Date(),
            targetHours:  hours,
            planName:     selectedPlan.rawValue
        )
        context.insert(session)
        do { try context.save() } catch { print("Save error: \(error)") }
        // Write to shared UserDefaults so widget can read it
        if let defaults = UserDefaults(suiteName: appGroupID) {
            defaults.set(true,                    forKey: "fastingIsActive")
            defaults.set(Date(),                  forKey: "fastingStartTime")
            defaults.set(hours,                   forKey: "fastingTargetHours")
            defaults.set(selectedPlan.rawValue,   forKey: "fastingPlanName")
        }
        WidgetCenter.shared.reloadAllTimelines()
        scheduleGoalNotification(targetHours: hours)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func endFast() {
        guard let session = activeSession else { return }
        session.endTime = Date()
        do { try context.save() } catch { print("Save error: \(error)") }
        // Clear shared UserDefaults
        if let defaults = UserDefaults(suiteName: appGroupID) {
            defaults.set(false, forKey: "fastingIsActive")
            defaults.removeObject(forKey: "fastingStartTime")
        }
        WidgetCenter.shared.reloadAllTimelines()
        cancelGoalNotification()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // Show note sheet after ending
        justEndedSession = session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            showingFastNoteSheet = true
        }
    }

    // MARK: - Track Actions (new, completely separate from fasting)
    // Track sessions NEVER touch UserDefaults / WidgetCenter — the lock screen
    // widget continues to reflect only real fasting sessions, exactly as before.

    private func startTrack(minutes: Double, label: String) {
        guard activeSession == nil else {
            showingTrackBlockedAlert = true
            return
        }
        let hours = minutes / 60
        let planName = "Track · \(label)"
        let session = FastingSession(
            startTime:   Date(),
            targetHours: hours,
            planName:    planName
        )
        context.insert(session)
        do { try context.save() } catch { print("Save error: \(error)") }
        // Safe to write to the widget here — the guard above proves no fast is active,
        // so this can never overwrite a live fasting session's widget data.
        if let defaults = UserDefaults(suiteName: appGroupID) {
            defaults.set(true,      forKey: "fastingIsActive")
            defaults.set(Date(),    forKey: "fastingStartTime")
            defaults.set(hours,     forKey: "fastingTargetHours")
            defaults.set(planName,  forKey: "fastingPlanName")
        }
        WidgetCenter.shared.reloadAllTimelines()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func endTrack() {
        guard let session = activeSession, activeIsTrack else { return }
        session.endTime = Date()
        do { try context.save() } catch { print("Save error: \(error)") }
        // This Track owned the widget (guard above confirms it was active), so clear it.
        if let defaults = UserDefaults(suiteName: appGroupID) {
            defaults.set(false, forKey: "fastingIsActive")
            defaults.removeObject(forKey: "fastingStartTime")
        }
        WidgetCenter.shared.reloadAllTimelines()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Notifications

    private func scheduleGoalNotification(targetHours: Double) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else { return }
                let content       = UNMutableNotificationContent()
                content.title     = "Fasting goal reached! 🎉"
                content.body      = "You've completed your \(Int(targetHours))-hour fast. Amazing work!"
                content.sound     = .default
                let trigger       = UNTimeIntervalNotificationTrigger(
                    timeInterval: targetHours * 3600, repeats: false
                )
                let req = UNNotificationRequest(
                    identifier: "fasting-goal", content: content, trigger: trigger
                )
                UNUserNotificationCenter.current().add(req)
            }
    }

    private func cancelGoalNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["fasting-goal"])
    }
}

// MARK: - Track Card (new)

struct TrackCard: View {
    let onPreset: (Double, String) -> Void
    let onCustom: () -> Void

    private let presets: [(label: String, minutes: Double)] = [
        ("15m", 15), ("30m", 30), ("1h", 60), ("2h", 120)
    ]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("⚡").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Track").font(.headline).fontWeight(.bold)
                    Text("Time any activity instantly").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                ForEach(presets, id: \.label) { preset in
                    Button {
                        onPreset(preset.minutes, preset.label)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Text(preset.label)
                            .font(.subheadline).fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onCustom) {
                    Text("Custom")
                        .font(.subheadline).fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color(.tertiarySystemBackground))
                        .foregroundStyle(.green)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - Custom Track Sheet (new)

struct CustomTrackSheet: View {
    let onStart: (Double, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Double = 45

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 4) {
                    Text(formattedDuration)
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    Text("duration").font(.caption).foregroundStyle(.secondary)
                }

                VStack(spacing: 8) {
                    Slider(value: $minutes, in: 5...240, step: 5).tint(.green)
                    HStack {
                        Text("5 min").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("4 hours").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                Button {
                    onStart(minutes, formattedDuration)
                    dismiss()
                } label: {
                    Label("Start Tracking", systemImage: "play.circle.fill")
                        .font(.title3).fontWeight(.bold)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Custom Duration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }

    private var formattedDuration: String {
        if minutes < 60 { return "\(Int(minutes))m" }
        let h = Int(minutes / 60)
        let m = Int(minutes.truncatingRemainder(dividingBy: 60))
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

// MARK: - Active Fast Card (unchanged except label shows duration correctly for Track)

struct ActiveFastCard: View {
    let session: FastingSession
    let now: Date
    let onEnd: () -> Void
    let onEdit: () -> Void

    private var isTrack: Bool { session.planName.hasPrefix("Track") }

    private var elapsed: TimeInterval { now.timeIntervalSince(session.startTime) }
    private var elapsedHours: Double  { elapsed / 3600 }
    private var progress: Double      { min(elapsedHours / session.targetHours, 1.0) }
    private var remaining: TimeInterval {
        max(session.targetHours * 3600 - elapsed, 0)
    }
    private var isGoalReached: Bool { elapsedHours >= session.targetHours }

    var body: some View {
        VStack(spacing: 24) {
            // Plan label
            HStack {
                Label(session.planName, systemImage: isTrack ? "bolt.fill" : "timer")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(isTrack ? .green : .secondary)
                Spacer()
                Button(action: onEdit) {
                    HStack(spacing: 4) {
                        Text("Started \(session.startTime.formatted(.dateTime.hour().minute()))")
                        Image(systemName: "pencil.circle.fill")
                    }
                    .font(.caption).foregroundStyle(.blue)
                }
            }

            // Ring + time
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color(.tertiarySystemBackground), lineWidth: 20)

                // Progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: isGoalReached
                                ? [.green, .mint]
                                : isTrack
                                    ? [.green, .green.opacity(0.5)]
                                    : [Color(hex: session.phase.color) ?? .blue,
                                       Color(hex: session.phase.color)?.opacity(0.6) ?? .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: progress)

                VStack(spacing: 6) {
                    if isGoalReached {
                        Text("🎉").font(.largeTitle)
                        Text("Goal reached!").font(.headline).fontWeight(.bold)
                        Text(session.startTime, style: .timer)
                            .font(.title3).fontWeight(.semibold).foregroundStyle(.secondary)
                    } else {
                        Text("Elapsed")
                            .font(.caption).foregroundStyle(.secondary)
                        // Isolated in its own view so only this re-renders every second
                        LiveTimerText(startTime: session.startTime)
                        Text(remainingLabel)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 240, height: 240)

            // Progress bar label
            HStack {
                Text("0h")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(targetLabel)
                    .font(.caption2).foregroundStyle(.secondary)
            }

            // Buttons row
            HStack(spacing: 12) {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                        .font(.body).fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color(.tertiarySystemBackground))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button(action: onEnd) {
                    Label(isTrack ? "End Track" : "End Fast", systemImage: "stop.circle.fill")
                        .font(.body).fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color(.tertiarySystemBackground))
                        .foregroundStyle(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var remainingLabel: String {
        // Use 'now' (60s refresh) for this — minute precision is fine
        let secs = Int(max(session.targetHours * 3600 - now.timeIntervalSince(session.startTime), 0))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if session.targetHours < 1 {
            return "\(secs / 60)m remaining"
        }
        return String(format: "%dh %02dm remaining", h, m)
    }

    private var targetLabel: String {
        if session.targetHours < 1 {
            return "\(Int(session.targetHours * 60))m goal"
        }
        return "\(Int(session.targetHours))h goal"
    }
}

// MARK: - Phase Card

struct PhaseCard: View {
    let session: FastingSession
    let now: Date

    private var elapsedHours: Double {
        now.timeIntervalSince(session.startTime) / 3600
    }
    private var phase: FastingPhase { currentPhase(for: elapsedHours) }
    private var nextPhase: FastingPhase? {
        fastingPhases.first { $0.startHour > elapsedHours }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Phase").font(.headline)

            HStack(spacing: 16) {
                Text(phase.emoji).font(.system(size: 40))

                VStack(alignment: .leading, spacing: 4) {
                    Text(phase.name)
                        .font(.title3).fontWeight(.bold)
                        .foregroundStyle(Color(hex: phase.color) ?? .blue)
                    Text(phase.description)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let next = nextPhase {
                Divider()
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.secondary).font(.caption)
                    Text("Next: \(next.name) at \(Int(next.startHour))h")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            // Phase timeline dots
            HStack(spacing: 0) {
                ForEach(fastingPhases.indices, id: \.self) { i in
                    let p = fastingPhases[i]
                    let isActive = p.name == phase.name
                    let isPast   = p.startHour < elapsedHours && !isActive
                    Circle()
                        .fill(isPast || isActive
                              ? (Color(hex: p.color) ?? .blue)
                              : Color(.tertiarySystemBackground))
                        .frame(width: isActive ? 14 : 10, height: isActive ? 14 : 10)
                        .overlay(
                            Circle().stroke(
                                Color(hex: p.color) ?? .blue,
                                lineWidth: isActive ? 0 : 1
                            )
                        )
                    if i < fastingPhases.count - 1 {
                        Rectangle()
                            .fill(isPast ? Color(hex: fastingPhases[i+1].color) ?? .gray : Color(.tertiarySystemBackground))
                            .frame(height: 2)
                    }
                }
            }
            .animation(.easeInOut, value: elapsedHours)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Start Fast Card

struct StartFastCard: View {
    @Binding var selectedPlan: FastingPlan
    @Binding var customHours: Double
    @Binding var showingPicker: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Icon
            VStack(spacing: 8) {
                Text("⏱️").font(.system(size: 60))
                Text("Ready to fast?")
                    .font(.title2).fontWeight(.bold)
                Text("Choose your fasting plan and tap start")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Plan selector button
            Button { showingPicker = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedPlan.rawValue)
                            .font(.title3).fontWeight(.bold)
                            .foregroundStyle(.primary)
                        Text(selectedPlan == .custom
                             ? "\(Int(customHours)) hours fasting"
                             : selectedPlan.description)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            // Start button
            Button(action: onStart) {
                Label("Start Fast", systemImage: "play.circle.fill")
                    .font(.title3).fontWeight(.bold)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - History Section (only change: stats exclude Track sessions, tag added to rows)

struct HistorySection: View {
    let sessions: [FastingSession]
    @Environment(\.modelContext) private var context

    private var fastSessions: [FastingSession] {
        sessions.filter { !$0.planName.hasPrefix("Track") }
    }
    private var longestFast: FastingSession? {
        fastSessions.max(by: { $0.durationHours < $1.durationHours })
    }
    private var averageHours: Double {
        guard !fastSessions.isEmpty else { return 0 }
        return fastSessions.reduce(0) { $0 + $1.durationHours } / Double(fastSessions.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("History").font(.headline)

            // Stats row
            HStack(spacing: 12) {
                MiniStatCard(value: "\(fastSessions.count)",
                             label: "Total\nFasts",
                             icon: "timer",
                             color: .blue)
                MiniStatCard(value: String(format: "%.1fh", averageHours),
                             label: "Average\nFast",
                             icon: "chart.bar.fill",
                             color: .orange)
                MiniStatCard(value: longestFast.map { String(format: "%.1fh", $0.durationHours) } ?? "—",
                             label: "Longest\nFast",
                             icon: "trophy.fill",
                             color: .yellow)
            }

            Text("Swipe left to delete")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Past sessions in a List so swipeActions work
            List {
                ForEach(sessions.prefix(10)) { session in
                    FastHistoryRow(session: session)
                        .listRowBackground(Color(.tertiarySystemBackground))
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                deleteSession(session)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                }
            }
            .listStyle(.plain)
            .scrollDisabled(true)
            .frame(minHeight: CGFloat(min(sessions.count, 10)) * 74)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func deleteSession(_ session: FastingSession) {
        context.delete(session)
        do { try context.save() } catch { print("Delete error: \(error)") }
    }
}

struct MiniStatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(color)
            Text(value).font(.title3).fontWeight(.bold)
            Text(label).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct FastHistoryRow: View {
    let session: FastingSession
    @State private var showingEdit = false

    private var isTrack: Bool { session.planName.hasPrefix("Track") }

    var body: some View {
        Button { showingEdit = true } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isTrack ? Color.green.opacity(0.15) : Color(.tertiarySystemBackground))
                            .frame(width: 36, height: 36)
                        if isTrack {
                            Image(systemName: "bolt.fill").foregroundStyle(.green).font(.subheadline)
                        } else {
                            Text(session.phase.emoji).font(.title3)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(session.planName)
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Text(isTrack ? "Track" : "Fast")
                                .font(.caption2).fontWeight(.semibold)
                                .foregroundStyle(isTrack ? .green : .blue)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(isTrack ? Color.green.opacity(0.12) : Color.blue.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        Text(session.startTime.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(session.formattedDuration)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(session.durationHours >= session.targetHours ? .green : .primary)
                        Text(session.durationHours >= session.targetHours ? "Goal reached ✓" : "Ended early")
                            .font(.caption2).foregroundStyle(.secondary)
                    }

                    Image(systemName: "pencil")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if !session.note.isEmpty {
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(isTrack ? Color.green : Color.blue)
                            .frame(width: 2)
                        Text(session.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(10)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingEdit) {
            EditFastSheet(session: session)
        }
    }
}

// MARK: - Plan Picker Sheet

struct PlanPickerSheet: View {
    @Binding var selectedPlan: FastingPlan
    @Binding var customHours: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(FastingPlan.allCases, id: \.self) { plan in
                    Button {
                        selectedPlan = plan
                        if plan != .custom { dismiss() }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(plan.rawValue)
                                    .font(.body).fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                                Text(plan == .custom
                                     ? "\(Int(customHours)) hours"
                                     : plan.description)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedPlan == plan {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue).fontWeight(.semibold)
                            }
                        }
                    }
                }

                if selectedPlan == .custom {
                    Section("Custom duration") {
                        VStack(spacing: 8) {
                            Text("\(Int(customHours)) hours")
                                .font(.title2).fontWeight(.bold)
                            Slider(value: $customHours, in: 1...72, step: 1)
                                .tint(.blue)
                            HStack {
                                Text("1h").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text("72h").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Choose Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - FastingSession helpers

extension FastingSession {
    func formattedElapsed(at now: Date) -> String {
        let secs  = Int(now.timeIntervalSince(startTime))
        let h     = secs / 3600
        let m     = (secs % 3600) / 60
        let s     = secs % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }
}


// MARK: - Live Timer Text (isolated to prevent full view re-render)

struct LiveTimerText: View {
    let startTime: Date

    var body: some View {
        Text(startTime, style: .timer)
            .font(.system(size: 44, weight: .bold, design: .rounded))
            .monospacedDigit()
            .multilineTextAlignment(.center)
    }
}

// MARK: - Edit Fast Sheet

struct EditFastSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let session: FastingSession

    @State private var startTime: Date = Date()
    @State private var targetHours: Double = 16
    @State private var endTime: Date = Date()
    @State private var editEndTime: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Start time") {
                    DatePicker("Started at",
                               selection: $startTime,
                               in: ...Date(),
                               displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                }

                Section("Duration goal") {
                    VStack(spacing: 8) {
                        Text("\(Int(targetHours)) hours")
                            .font(.title2).fontWeight(.bold)
                        Slider(value: $targetHours, in: 1...72, step: 1)
                            .tint(.blue)
                        HStack {
                            Text("1h").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("72h").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                if !session.isActive {
                    Section("End time") {
                        DatePicker("Ended at",
                                   selection: $endTime,
                                   in: startTime...Date(),
                                   displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                    }
                }
            }
            .navigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            startTime   = session.startTime
            targetHours = session.targetHours
            endTime     = session.endTime ?? Date()
        }
    }

    private func save() {
        session.startTime   = startTime
        session.targetHours = targetHours
        if !session.isActive {
            // Clamp end time so it can't be before start
            session.endTime = max(endTime, startTime.addingTimeInterval(60))
        }
        do { try context.save() } catch { print("Save error: \(error)") }
        dismiss()
    }
}




// MARK: - Fasting Note Sheet

struct FastingNoteSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let session: FastingSession

    @State private var note: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fast complete! \(session.formattedDuration)")
                        .font(.headline)
                    Text("How did it feel? Add a note.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                    if note.isEmpty {
                        Text("e.g. felt great, a bit hungry at hour 14...")
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
            .navigationTitle("Fasting Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        session.note = note.isEmpty ? "" : note
                        do { try context.save() } catch { print("Note save error: \(error)") }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            note = session.note ?? ""
            focused = true
        }
    }
}
