import Foundation

struct ArenaPoint: Codable, Equatable {
    var x: Double
    var y: Double

    static let zero = Self(x: 0, y: 0)

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(radius: Double, angle: Double) {
        self.init(x: radius * cos(angle), y: radius * sin(angle))
    }

    var radius: Double { hypot(x, y) }
}

struct ArenaRules {
    static let version = 1
    static let step = 1.0 / 120
    static let core = 20.0
    static let minimum = 28.0
    static let maximum = 308.0
    static let spawn = 326.0
    static let captureGrace = 6.0
    static let mineGrace = 6.0
    static let cleanseMinimum = 3
    static let recovery = 0.32

    static func expandRing(_ radius: Double) -> Double {
        let resistance = max(0, min(1, (radius - 240) / (maximum - 240)))
        return min(maximum, radius + (266 - resistance * 198) * step)
    }
}

struct GameplayRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func nextUnit() -> Double {
        state &+= 0x9e3779b97f4a7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return Double((value ^ (value >> 31)) >> 11) / 9_007_199_254_740_992
    }
}

enum EnemyKind: String, Codable, CaseIterable {
    case drifter, lancer, spiral, splitter, charger, shard, starter

    var speed: Double {
        switch self {
        case .drifter: 52
        case .lancer: 90
        case .spiral: 56
        case .splitter: 42
        case .charger: 48
        case .shard: 64
        case .starter: 0
        }
    }

    func moveEnemy(_ enemy: inout Enemy, step: Double) {
        switch self {
        case .spiral:
            enemy.angle += enemy.angularVelocity * step
            enemy.radius -= enemy.speed * step
        case .charger:
            enemy.phase += step * 6.2
            let pulse = 0.35 + 1.15 * max(0, sin(enemy.phase))
            enemy.radius -= enemy.speed * pulse * step
        default:
            enemy.radius -= enemy.speed * step
        }
    }

    var splitsOnCapture: Bool { self == .splitter }
}

struct Enemy {
    let id: Int
    let kind: EnemyKind
    var angle: Double
    var radius: Double
    var speed: Double
    var angularVelocity = 0.0
    var phase = 0.0

    var point: ArenaPoint { ArenaPoint(radius: radius, angle: angle) }
}

struct Hazard {
    enum Motion {
        case ember(angle: Double, target: Double, radius: Double)
        case comet(velocity: ArenaPoint)
    }

    let id: Int
    var motion: Motion
    var point: ArenaPoint
    var fuse: Double
    var total: Double
    var armed = true

    var radius: Double {
        if case let .ember(_, _, radius) = motion { return radius }
        return point.radius
    }

    var isComet: Bool {
        if case .comet = motion { return true }
        return false
    }

    mutating func advanceHazard(_ step: Double) -> Bool {
        switch motion {
        case let .ember(angle, target, radius):
            let nextRadius = max(radius, min(target, radius + 280 * step))
            point = ArenaPoint(radius: nextRadius, angle: angle)
            motion = .ember(angle: angle, target: target, radius: nextRadius)
            fuse -= step
            if fuse <= 0.15 { armed = false }
            return fuse > 0
        case let .comet(velocity):
            point.x += velocity.x * step
            point.y += velocity.y * step
            return point.radius <= ArenaRules.spawn + 18
        }
    }
}

struct CometWarning {
    let id: Int
    let origin: ArenaPoint
    let end: ArenaPoint
    let velocity: ArenaPoint
    var countdown = 0.95
}

struct LockState: Equatable {
    var enemies = 0
    var hazards = 0

    var canCleanse: Bool { enemies >= ArenaRules.cleanseMinimum }
}

struct SnapSelection {
    let enemies: [Enemy]
    let hazards: [Hazard]
    let grazesMine: Bool

    var isCleanse: Bool { enemies.count >= ArenaRules.cleanseMinimum }

    init(radius: Double, enemies: [Enemy], hazards: [Hazard]) {
        self.enemies = enemies.filter { $0.radius <= radius + ArenaRules.captureGrace }
        let trigger = radius - ArenaRules.mineGrace
        self.hazards = hazards.filter { $0.armed && $0.radius <= trigger }
        grazesMine = hazards.contains { $0.armed && $0.radius > trigger && $0.radius <= radius + 22 }
    }
}

enum ScoreBonus: String, CaseIterable, Codable {
    case mineBreak, closeCut, mineGraze, fullDraw
}

struct ScoreAward: Equatable {
    let base: Int
    let bonuses: [ScoreBonus: Int]
    var total: Int { base + bonuses.values.reduce(0, +) }
}

struct ScoreRules {
    func calculateAward(_ snap: SnapSelection, radius: Double) -> ScoreAward {
        let kills = snap.enemies.count
        var bonuses: [ScoreBonus: Int] = [:]
        if snap.isCleanse && !snap.hazards.isEmpty { bonuses[.mineBreak] = 50 * snap.hazards.count }
        if snap.enemies.contains(where: { $0.radius <= 40 }) { bonuses[.closeCut] = 50 }
        if snap.grazesMine { bonuses[.mineGraze] = 40 }
        if radius >= ArenaRules.maximum - 24 { bonuses[.fullDraw] = 40 }
        return ScoreAward(base: 10 * kills * kills, bonuses: bonuses)
    }
}

struct RunStats: Codable, Equatable {
    var score = 0
    var duration = 0.0
    var kills = 0
    var maxSnap = 0
    var cleanses = 0
    var minesBroken = 0
    var bonuses: [ScoreBonus: Int] = [:]

    mutating func recordSnap(_ snap: SnapSelection, award: ScoreAward) {
        score += award.total
        kills += snap.enemies.count
        maxSnap = max(maxSnap, snap.enemies.count)
        if snap.isCleanse {
            cleanses += 1
            minesBroken += snap.hazards.count
        }
        for bonus in award.bonuses.keys { bonuses[bonus, default: 0] += 1 }
    }
}

enum Defeat: Codable, Equatable {
    case core(EnemyKind)
    case mine(comet: Bool, locked: Int)
    case overload
}

struct DeathFocus: Equatable {
    let cause: Defeat
    let point: ArenaPoint
    let radius: Double
}

enum Lesson: Int, CaseIterable, Codable {
    case capture, multiKill, mine, overload
}

enum GameMode: Codable, Equatable {
    case classic
    case practice(Lesson)
}
