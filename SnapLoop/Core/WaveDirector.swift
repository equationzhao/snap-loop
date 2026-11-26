import Foundation

struct WaveDirector {
    struct Spawn {
        let kind: EnemyKind
        let angle: Double
        let offset: Double
        let speedScale: Double
    }

    private static let thresholds = [0.0, 22, 52, 92, 145]
    private static let tempo = [94.0, 104, 114, 122, 132]
    private(set) var stage = 0
    private var wave = 0
    private var waveTimer = 0.45
    private var cometTimer = 8.0
    private var beatTimer = 0.4
    private var beat = 0

    mutating func advanceWaves(
        stats: RunStats, comets: Int, random: inout GameplayRandom
    ) -> (spawns: [Spawn], stageChanged: Bool, beat: Bool?, comet: Bool) {
        let progress = stats.duration + Double(stats.kills) * 0.65
        let newStage = Self.thresholds.lastIndex { progress >= $0 } ?? 0
        let stageChanged = newStage != stage
        stage = newStage

        beatTimer -= ArenaRules.step
        var accent: Bool?
        if beatTimer <= 0 {
            beatTimer += 60 / Self.tempo[stage]
            accent = beat.isMultiple(of: 4)
            beat += 1
        }

        var launchCometWarning = false
        if stage >= 2 {
            cometTimer -= ArenaRules.step
            if cometTimer <= 0 && comets < (stage == 4 ? 2 : 1) {
                launchCometWarning = true
                cometTimer = stage == 4 ? 5.8 : 7.8
            }
        }

        waveTimer -= ArenaRules.step
        let spawns = waveTimer <= 0 ? spawnWave(progress: progress, random: &random) : []
        return (spawns, stageChanged, accent, launchCometWarning)
    }

    private mutating func spawnWave(progress: Double, random: inout GameplayRandom) -> [Spawn] {
        let angle = random.nextUnit() * 2 * .pi
        let speed = 1 + min(0.55, max(0, progress - 25) * 0.003)
        func spawn(_ kind: EnemyKind, _ offsetAngle: Double = 0, _ offsetRadius: Double = 0) -> Spawn {
            Spawn(kind: kind, angle: angle + offsetAngle, offset: offsetRadius, speedScale: wave <= 2 ? 1 : speed)
        }

        wave += 1
        switch wave {
        case 1:
            waveTimer = 2.3
            return [spawn(.drifter)]
        case 2:
            waveTimer = 3.1
            return [spawn(.drifter), spawn(.drifter, 2.05, 16), spawn(.drifter, -2.05, 30)]
        default: break
        }

        let roll = random.nextUnit()
        let breather = wave.isMultiple(of: 6)
        switch stage {
        case 0:
            waveTimer = breather ? 2.7 : 2.1
            let count = roll < 0.45 ? 3 : 2
            return (0..<count).map { index in
                spawn(.drifter, Double(index) * 2 * .pi / Double(count) + (random.nextUnit() - 0.5) * 0.5, Double(index) * 18)
            }
        case 1:
            waveTimer = breather ? 2.5 : 1.85
            if roll < 0.55 { return [spawn(.drifter), spawn(.drifter, 2.2, 14), spawn(.lancer, 4.2, 45)] }
            return [spawn(.lancer), spawn(.drifter, .pi, 10)]
        case 2:
            waveTimer = breather ? 2.35 : 1.68
            if roll < 0.4 { return [spawn(.spiral), spawn(.spiral, .pi, 16), spawn(.drifter, 1.5, 24)] }
            if roll < 0.75 { return [spawn(.lancer, 0, 20), spawn(.spiral, 2.1)] }
            return [spawn(.drifter), spawn(.drifter, 2.09, 14), spawn(.drifter, 4.18, 28)]
        case 3:
            waveTimer = breather ? 2.25 : 1.55
            if roll < 0.45 { return [spawn(.splitter), spawn(.drifter, 2.4, 22)] }
            if roll < 0.78 { return [spawn(.lancer, 0, 26), spawn(.spiral, 2), spawn(.drifter, -2, 12)] }
            return [spawn(.splitter), spawn(.lancer, .pi, 35)]
        default:
            waveTimer = (breather ? 2.1 : 1.45) * max(0.72, 1 - (progress - 145) * 0.0012)
            if roll < 0.35 { return [spawn(.charger), spawn(.charger, .pi, 18), spawn(.drifter, 1.57, 25)] }
            if roll < 0.68 { return [spawn(.splitter), spawn(.lancer, 2.1, 30), spawn(.spiral, -2.1, 12)] }
            return [spawn(.charger, 0, 15), spawn(.lancer, 2.4, 38), spawn(.drifter, -1.8)]
        }
    }
}
