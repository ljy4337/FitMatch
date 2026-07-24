import Foundation

struct BodyShapePreferences: Codable, Equatable {
    var hasBroadShoulders = false
    var hasDevelopedChest = false
    var hasProminentAbdomen = false
    var hasProminentLowerWaist = false
    var hasDevelopedHips = false
    var hasDevelopedThighs = false

    static let none = BodyShapePreferences()

    var preferredMeasurementKinds: Set<MeasurementKind> {
        var kinds = Set<MeasurementKind>()
        if hasBroadShoulders { kinds.insert(.shoulder) }
        if hasDevelopedChest { kinds.insert(.chest) }
        if hasProminentLowerWaist { kinds.insert(.waist) }
        if hasDevelopedHips { kinds.insert(.hip) }
        if hasDevelopedThighs { kinds.insert(.thigh) }
        return kinds
    }
}

struct BodyShapeSettingsStore {
    static let dataVersion = 1

    private enum Key {
        static let preferences = "FitMatch.bodyShape.preferences"
        static let completedVersion = "FitMatch.bodyShape.completedVersion"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> BodyShapePreferences {
        guard let data = defaults.data(forKey: Key.preferences),
              let value = try? JSONDecoder().decode(BodyShapePreferences.self, from: data) else {
            return .none
        }
        return value
    }

    func save(_ preferences: BodyShapePreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Key.preferences)
    }

    var completedVersion: Int {
        defaults.integer(forKey: Key.completedVersion)
    }

    func markCompleted() {
        defaults.set(Self.dataVersion, forKey: Key.completedVersion)
    }
}
