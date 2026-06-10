import SwiftData
import Foundation

@Model final class FavoriteFood {
    var id: UUID
    var name: String
    var kcalPer100g: Double
    var proteinPer100g: Double?
    var carbsPer100g: Double?
    var fatPer100g: Double?
    var createdAt: Date

    init(name: String, kcalPer100g: Double,
         proteinPer100g: Double? = nil,
         carbsPer100g: Double? = nil,
         fatPer100g: Double? = nil) {
        self.id            = UUID()
        self.name          = name
        self.kcalPer100g   = kcalPer100g
        self.proteinPer100g = proteinPer100g
        self.carbsPer100g  = carbsPer100g
        self.fatPer100g    = fatPer100g
        self.createdAt     = Date()
    }
}
