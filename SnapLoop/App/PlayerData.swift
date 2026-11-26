import Foundation

struct PlayerSettings: Codable, Equatable {
    var volume = 0.65
    var haptics = true
    var shake = true
    var flash = 0.65
    var showMarkers = false
    var tutorialSeen = false
}

struct RunRecord: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    let rulesVersion: Int
    let stats: RunStats
    let cause: Defeat
}

struct PlayerRecords: Codable {
    var bestScore = 0
    var longest = 0.0
    var maxSnap = 0
    var cleanses = 0
    var minesBroken = 0
    var runs = 0
    var bonuses: [ScoreBonus: Int] = [:]
    var recent: [RunRecord] = []

    mutating func recordRun(_ run: RunRecord) -> Bool {
        let newBest = run.stats.score > bestScore
        bestScore = max(bestScore, run.stats.score)
        longest = max(longest, run.stats.duration)
        maxSnap = max(maxSnap, run.stats.maxSnap)
        cleanses += run.stats.cleanses
        minesBroken += run.stats.minesBroken
        runs += 1
        for (bonus, count) in run.stats.bonuses { bonuses[bonus, default: 0] += count }
        recent = Array(([run] + recent).prefix(20))
        return newBest
    }
}

@MainActor
struct PlayerData {
    private let defaults: UserDefaults
    private let settingsKey = "snapLoop.settings.v1"
    private let recordsKey = "snapLoop.records.v1"

    init() {
        #if DEBUG
        if let suite = ProcessInfo.processInfo.environment["SNAP_LOOP_STORAGE_SUITE"],
           let isolatedDefaults = UserDefaults(suiteName: suite) {
            defaults = isolatedDefaults
            return
        }
        #endif
        defaults = .standard
    }

    func loadSettings() -> PlayerSettings { load(settingsKey) ?? PlayerSettings() }
    func loadRecords() -> PlayerRecords { load(recordsKey) ?? PlayerRecords() }
    func saveSettings(_ settings: PlayerSettings) { save(settings, key: settingsKey) }
    func saveRecords(_ records: PlayerRecords) { save(records, key: recordsKey) }

    private func load<Value: Decodable>(_ key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private func save<Value: Encodable>(_ value: Value, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    #if DEBUG
    func saveReplay(_ replay: Replay) {
        guard case .classic = replay.mode,
              let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let data = try? JSONEncoder().encode(replay) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appending(path: "last-classic-run.json"), options: .atomic)
        } catch {
            NSLog("Replay save failed: %@", error.localizedDescription)
        }
    }
    #endif
}
