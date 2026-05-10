import SwiftData
import SwiftUI

// MARK: - Fasting Plan

enum FastingPlan: String, Codable, CaseIterable {
    case sixteen8  = "16:8"
    case eighteen6 = "18:6"
    case twenty4   = "20:4"
    case omad      = "OMAD"
    case custom    = "Custom"

    var targetHours: Double {
        switch self {
        case .sixteen8:  return 16
        case .eighteen6: return 18
        case .twenty4:   return 20
        case .omad:      return 23
        case .custom:    return 16  // overridden by customHours
        }
    }

    var description: String {
        switch self {
        case .sixteen8:  return "16 hours fasting, 8 hours eating"
        case .eighteen6: return "18 hours fasting, 6 hours eating"
        case .twenty4:   return "20 hours fasting, 4 hours eating"
        case .omad:      return "One meal a day, ~23 hours fasting"
        case .custom:    return "Your custom fasting window"
        }
    }
}

// MARK: - Fasting Phase

struct FastingPhase {
    let name: String
    let emoji: String
    let description: String
    let color: String      // hex
    let startHour: Double
    let endHour: Double
}

let fastingPhases: [FastingPhase] = [
    FastingPhase(name: "Fed State",      emoji: "🍽️", description: "Digesting your last meal",          color: "#8E8E93", startHour: 0,  endHour: 4),
    FastingPhase(name: "Early Fast",     emoji: "⚡",  description: "Blood sugar stabilising",           color: "#30D158", startHour: 4,  endHour: 8),
    FastingPhase(name: "Fat Burning",    emoji: "🔥",  description: "Body switching to fat for fuel",    color: "#FF9F0A", startHour: 8,  endHour: 12),
    FastingPhase(name: "Deep Ketosis",   emoji: "💪",  description: "Ketone production increasing",      color: "#0A84FF", startHour: 12, endHour: 18),
    FastingPhase(name: "Autophagy",      emoji: "🧬",  description: "Cellular repair and regeneration",  color: "#BF5AF2", startHour: 18, endHour: 24),
    FastingPhase(name: "Extended Fast",  emoji: "🏆",  description: "Deep metabolic reset underway",     color: "#FF453A", startHour: 24, endHour: 999),
]

func currentPhase(for elapsedHours: Double) -> FastingPhase {
    fastingPhases.last(where: { elapsedHours >= $0.startHour }) ?? fastingPhases[0]
}

// MARK: - FastingSession SwiftData Model

@Model
final class FastingSession {
    var id: UUID
    var startTime: Date
    var endTime: Date?           // nil = currently active
    var targetHours: Double
    var planName: String         // stores FastingPlan.rawValue or "Custom"
    var note: String

    init(startTime: Date = Date(),
         targetHours: Double = 16,
         planName: String = FastingPlan.sixteen8.rawValue,
         note: String = "") {
        self.id          = UUID()
        self.startTime   = startTime
        self.endTime     = nil
        self.targetHours = targetHours
        self.planName    = planName
        self.note        = note
    }

    var isActive: Bool { endTime == nil }

    var elapsedSeconds: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }

    var elapsedHours: Double { elapsedSeconds / 3600 }

    var duration: TimeInterval {
        guard let end = endTime else { return elapsedSeconds }
        return end.timeIntervalSince(startTime)
    }

    var durationHours: Double { duration / 3600 }

    var progress: Double {
        min(elapsedHours / targetHours, 1.0)
    }

    var phase: FastingPhase { currentPhase(for: elapsedHours) }

    var formattedDuration: String {
        let total = Int(duration)
        let h = total / 3600
        let m = (total % 3600) / 60
        return String(format: "%dh %02dm", h, m)
    }
}
