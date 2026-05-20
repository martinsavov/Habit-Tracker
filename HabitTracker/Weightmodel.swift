import SwiftData
import SwiftUI

@Model
final class WeightEntry {
    var id: UUID
    var date: Date
    var kg: Double

    init(date: Date = Date(), kg: Double) {
        self.id   = UUID()
        self.date = date
        self.kg   = kg
    }
}
