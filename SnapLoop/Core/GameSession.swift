import Foundation

enum InputCommand: String, Codable {
    case press, release, detach
}

enum PauseReason: String, Codable {
    case player, cancellation, inactive, audio, frameGap
}

struct Replay: Codable {
    struct Entry: Codable {
        let tick: Int
        let command: InputCommand?
        var pause: PauseReason?
    }

    let rulesVersion: Int
    let seed: UInt64
    let mode: GameMode
    var entries: [Entry] = []
    var finalTick = 0
    var stats = RunStats()
    var defeat: Defeat?

    func reproduceRun() -> GameCore? {
        guard rulesVersion == ArenaRules.version, finalTick >= 0 else { return nil }
        var core = GameCore(mode: mode, seed: seed)
        var index = entries.startIndex
        for tick in 0...finalTick {
            while index < entries.endIndex, entries[index].tick == tick {
                if let command = entries[index].command { core.applyInput(command) }
                index += 1
            }
            if tick < finalTick { core.advanceStep() }
            _ = core.drainEvents()
        }
        return index == entries.endIndex ? core : nil
    }
}

struct GameSession {
    enum State: Equatable {
        case ready, playing, paused, resumeArmed, dead, results, lessonComplete
    }

    private(set) var core: GameCore
    private(set) var state = State.ready
    private(set) var replay: Replay
    private var touch: Int?
    private var queue: [InputCommand] = []
    private var accumulated = 0.0
    private var deathDelay = 0.0

    init(mode: GameMode, seed: UInt64) {
        core = GameCore(mode: mode, seed: seed)
        replay = Replay(rulesVersion: ArenaRules.version, seed: seed, mode: mode)
    }

    mutating func beginTouch(_ id: Int) -> Bool {
        guard touch == nil, state == .ready || state == .playing || state == .resumeArmed else { return false }
        touch = id
        state = .playing
        queue.append(.press)
        return true
    }

    mutating func endTouch(_ id: Int) {
        guard touch == id else { return }
        touch = nil
        if state == .playing { queue.append(.release) }
    }

    mutating func cancelTouch(_ id: Int) -> Bool {
        guard touch == id else { return false }
        pauseRun(.cancellation)
        return true
    }

    mutating func pauseRun(_ reason: PauseReason) {
        touch = nil
        queue.removeAll()
        accumulated = 0
        guard state == .playing || state == .resumeArmed else { return }
        recordInput(.detach, pause: reason)
        state = .paused
    }

    mutating func armResume() {
        guard state == .paused else { return }
        state = .resumeArmed
    }

    mutating func advanceFrame(_ elapsed: Double) -> [GameEvent] {
        if state == .dead {
            if elapsed < 0.25 { deathDelay += elapsed }
            if deathDelay >= 0.42 { state = .results }
            return []
        }
        guard state == .playing && elapsed >= 0 else { return [] }
        guard elapsed < 0.25 else {
            pauseRun(.frameGap)
            return []
        }
        accumulated += min(elapsed, 0.1)
        var events: [GameEvent] = []
        while accumulated + 1e-10 >= ArenaRules.step, state == .playing {
            accumulated -= ArenaRules.step
            while core.hitStop == 0 && !queue.isEmpty && core.death == nil && !core.lessonComplete {
                recordInput(queue.removeFirst())
            }
            core.advanceStep()
            if core.death != nil || core.lessonComplete {
                state = core.lessonComplete ? .lessonComplete : .dead
                touch = nil
                queue.removeAll()
            }
            events += core.drainEvents()
        }
        replay.finalTick = core.tick
        replay.stats = core.stats
        replay.defeat = core.death?.cause
        return events
    }

    private mutating func recordInput(_ input: InputCommand, pause: PauseReason? = nil) {
        replay.entries.append(.init(tick: core.tick, command: input, pause: pause))
        core.applyInput(input)
    }
}
