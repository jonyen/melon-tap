import Foundation

/// What the melon actually turned out to be, recorded after cutting it. This is the ground
/// truth the whole logging design exists to collect.
enum Outcome: String, Codable, CaseIterable, Identifiable {
    case ripe
    case unripe
    case overripe
    case mushy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ripe: return "Ripe"
        case .unripe: return "Unripe"
        case .overripe: return "Overripe"
        case .mushy: return "Mushy"
        }
    }
}
