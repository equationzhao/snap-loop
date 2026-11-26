import Foundation

enum GameEvent {
    case touch, charge, lock(cleanseReady: Bool), warning, stage, beat(accent: Bool), fuse
    case snap(SnapEffect)
    case defeat(DeathFocus)
    case lessonComplete
}

struct SnapEffect {
    let radius: Double
    let targets: [ArenaPoint]
    let award: ScoreAward?
    let isCleanse: Bool
}

struct GameCore {
    let mode: GameMode
    private(set) var enemies: [Enemy] = []
    private(set) var hazards: [Hazard] = []
    private(set) var warnings: [CometWarning] = []
    private(set) var stats = RunStats()
    private(set) var ring = ArenaRules.minimum
    private(set) var charging = false
    private(set) var recovery = 0.0
    private(set) var hitStop = 0.0
    private(set) var tick = 0
    private(set) var death: DeathFocus?
    private(set) var lessonComplete = false
    private var events: [GameEvent] = []
    private var holding = false
    private var lastLocks = LockState()
    private var director = WaveDirector()
    private var random: GameplayRandom
    private var nextID = 0
    private let scoring = ScoreRules()

    var stage: Int { director.stage }
    var locks: LockState {
        guard charging else { return LockState() }
        let selection = selectTargets()
        return LockState(enemies: selection.enemies.count, hazards: selection.hazards.count)
    }

    init(mode: GameMode, seed: UInt64) {
        self.mode = mode
        random = GameplayRandom(seed: seed)
        guard case let .practice(lesson) = mode else { return }
        switch lesson {
        case .capture:
            spawnEnemy(.starter, angle: 0.95, radius: 134)
        case .multiKill, .mine:
            for (index, radius) in [106.0, 138, 160].enumerated() {
                spawnEnemy(.starter, angle: 0.9 + Double(index) * 2.1, radius: radius)
            }
            if lesson == .mine { spawnEmber(angle: -0.15, radius: 84, fuse: 3600) }
        case .overload: break
        }
    }

    mutating func applyInput(_ command: InputCommand) {
        guard death == nil, !lessonComplete else { return }
        switch command {
        case .press:
            holding = true
            if recovery > 0 { events.append(.touch) }
            else { startCharge() }
        case .release:
            guard holding else { return }
            holding = false
            if charging { executeSnap() }
        case .detach:
            holding = false
        }
    }

    mutating func advanceStep() {
        guard death == nil, !lessonComplete else { return }
        tick += 1
        let step = ArenaRules.step
        if hitStop > 0 {
            hitStop = max(0, hitStop - step)
            return
        }
        if recovery > 0 {
            recovery = max(0, recovery - step)
            if recovery == 0 && holding { startCharge() }
        }
        if charging {
            let oldRing = ring
            ring = ArenaRules.expandRing(ring)
            if oldRing < 250 && ring >= 250 { events.append(.warning) }
            if ring >= ArenaRules.maximum {
                if mode == .practice(.overload) { completeLesson() }
                else { triggerDefeat(.overload, point: ArenaPoint(x: 0, y: ring)) }
                return
            }
        }
        stats.duration += step
        if mode == .classic { advanceWaves() }
        advanceHazards()
        for index in enemies.indices.reversed() {
            let kind = enemies[index].kind
            kind.moveEnemy(&enemies[index], step: step)
            if enemies[index].radius <= ArenaRules.core + 1 {
                triggerDefeat(.core(kind), point: enemies[index].point)
                return
            }
        }
        if charging {
            let current = locks
            if current.canCleanse && !lastLocks.canCleanse { events.append(.lock(cleanseReady: true)) }
            else if current.hazards > lastLocks.hazards && !current.canCleanse { events.append(.warning) }
            else if current.enemies > lastLocks.enemies { events.append(.lock(cleanseReady: false)) }
            lastLocks = current
        }
    }

    mutating func drainEvents() -> [GameEvent] {
        defer { events.removeAll(keepingCapacity: true) }
        return events
    }

    private func selectTargets() -> SnapSelection {
        SnapSelection(radius: ring, enemies: enemies, hazards: hazards)
    }

    private mutating func startCharge() {
        if !charging { lastLocks = LockState() }
        charging = true
        events.append(.charge)
    }

    private mutating func executeSnap() {
        let radius = ring
        let snap = selectTargets()
        charging = false
        if !snap.isCleanse, let mine = snap.hazards.min(by: { $0.fuse < $1.fuse }) {
            triggerDefeat(.mine(comet: mine.isComet, locked: snap.enemies.count), point: mine.point)
            return
        }
        ring = ArenaRules.minimum
        guard !snap.enemies.isEmpty else {
            recovery = ArenaRules.recovery
            events.append(.snap(SnapEffect(radius: radius, targets: [], award: nil, isCleanse: false)))
            return
        }
        let award = scoring.calculateAward(snap, radius: radius)
        events.append(.snap(SnapEffect(radius: radius, targets: snap.enemies.map(\.point) + snap.hazards.map(\.point), award: award, isCleanse: snap.isCleanse)))

        if case let .practice(lesson) = mode {
            if lesson == .capture || (lesson == .multiKill && snap.isCleanse) || (lesson == .mine && !snap.hazards.isEmpty) {
                completeLesson()
            }
            return
        }

        stats.recordSnap(snap, award: award)
        let captured = Set(snap.enemies.map(\.id))
        enemies.removeAll { captured.contains($0.id) }
        if snap.isCleanse {
            let purified = Set(snap.hazards.map(\.id))
            hazards.removeAll { purified.contains($0.id) }
            for index in hazards.indices where !hazards[index].isComet && hazards[index].armed {
                hazards[index].fuse -= 1.5
                if hazards[index].fuse <= 0.12 {
                    hazards[index].fuse = 0.1
                    hazards[index].armed = false
                }
            }
        }
        let baseFuse = min(3.35, 2.65 + Double(stage) * 0.16)
        for enemy in snap.enemies {
            if enemy.kind.splitsOnCapture {
                for offset in [-0.24, 0.24] {
                    spawnEnemy(.shard, angle: enemy.angle + offset, radius: min(ArenaRules.maximum - 24, enemy.radius + 42))
                }
            } else if !snap.isCleanse {
                spawnEmber(angle: enemy.angle, radius: enemy.radius, fuse: snap.enemies.count == 2 ? baseFuse * 0.62 : baseFuse)
            }
        }
        hitStop = snap.isCleanse ? 0.055 : (snap.grazesMine || award.bonuses[.closeCut] != nil ? 0.038 : 0.02)
    }

    private mutating func advanceWaves() {
        let wave = director.advanceWaves(stats: stats, comets: hazards.filter(\.isComet).count + warnings.count, random: &random)
        if wave.stageChanged { events.append(.stage) }
        if let accent = wave.beat { events.append(.beat(accent: accent)) }
        if wave.comet { spawnCometWarning() }
        for spawn in wave.spawns {
            spawnEnemy(spawn.kind, angle: spawn.angle, radius: ArenaRules.spawn + spawn.offset, scale: spawn.speedScale)
        }
        for index in warnings.indices.reversed() {
            warnings[index].countdown -= ArenaRules.step
            if warnings[index].countdown <= 0 {
                let warning = warnings.remove(at: index)
                hazards.append(Hazard(id: warning.id, motion: .comet(velocity: warning.velocity), point: warning.origin, fuse: 99, total: 99))
            }
        }
    }

    private mutating func advanceHazards() {
        for index in hazards.indices.reversed() {
            let wasArmed = hazards[index].armed
            if !hazards[index].advanceHazard(ArenaRules.step) { hazards.remove(at: index) }
            else if wasArmed && !hazards[index].armed { events.append(.fuse) }
        }
    }

    private mutating func spawnEnemy(_ kind: EnemyKind, angle: Double, radius: Double, scale: Double = 1) {
        var enemy = Enemy(id: makeID(), kind: kind, angle: angle, radius: radius, speed: kind.speed * scale)
        switch kind {
        case .spiral: enemy.angularVelocity = (random.nextUnit() < 0.5 ? -0.68 : 0.68) * scale
        case .charger: enemy.phase = random.nextUnit() * 2 * .pi
        case .shard: enemy.speed += Double(stage) * 4
        default: break
        }
        enemies.append(enemy)
    }

    private mutating func spawnEmber(angle: Double, radius: Double, fuse: Double) {
        let target = max(78, min(ArenaRules.maximum - 22, radius))
        let hazard = Hazard(id: makeID(), motion: .ember(angle: angle, target: target, radius: radius), point: ArenaPoint(radius: radius, angle: angle), fuse: fuse, total: fuse)
        hazards.append(hazard)
    }

    private mutating func spawnCometWarning() {
        let angle = random.nextUnit() * 2 * .pi
        let offset = 128 + random.nextUnit() * 82
        let sign = random.nextUnit() < 0.5 ? -1.0 : 1.0
        let half = sqrt(pow(ArenaRules.spawn, 2) - offset * offset)
        let middle = ArenaPoint(radius: offset, angle: angle)
        let tangent = ArenaPoint(x: -sin(angle) * sign, y: cos(angle) * sign)
        let start = ArenaPoint(x: middle.x - tangent.x * half, y: middle.y - tangent.y * half)
        let end = ArenaPoint(x: middle.x + tangent.x * half, y: middle.y + tangent.y * half)
        warnings.append(CometWarning(id: makeID(), origin: start, end: end, velocity: ArenaPoint(x: tangent.x * 76, y: tangent.y * 76)))
    }

    private mutating func makeID() -> Int {
        nextID += 1
        return nextID
    }

    private mutating func completeLesson() {
        lessonComplete = true
        charging = false
        holding = false
        events.append(.lessonComplete)
    }

    private mutating func triggerDefeat(_ cause: Defeat, point: ArenaPoint) {
        let focus = DeathFocus(cause: cause, point: point, radius: charging || point.radius > ArenaRules.core + 1 ? ring : ArenaRules.minimum)
        death = focus
        charging = false
        holding = false
        events.append(.defeat(focus))
    }
}
