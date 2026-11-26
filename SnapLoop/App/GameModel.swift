import Foundation
import Observation

struct GameHUD: Equatable {
    var score = 0
    var stage = 0
    var locks = LockState()
    var charging = false
    var recovering = false
    var danger = false
}

@MainActor @Observable
final class GameModel {
    private(set) var mode: GameMode?
    private(set) var state = GameSession.State.ready
    private(set) var hud = GameHUD()
    private(set) var records: PlayerRecords
    private(set) var result: RunRecord?
    private(set) var newBest = false
    private(set) var practiceFailed = false
    var reduceMotion = false
    var highContrast = false
    var differentiateWithoutColor = false
    var settings: PlayerSettings {
        didSet {
            storage.saveSettings(settings)
            feedback.applySettings(settings)
        }
    }

    @ObservationIgnored private var session: GameSession?
    @ObservationIgnored private let storage = PlayerData()
    @ObservationIgnored private let feedback = Feedback()
    @ObservationIgnored lazy var scene = ArenaScene(model: self)

    var core: GameCore? { session?.core }

    init() {
        settings = storage.loadSettings()
        records = storage.loadRecords()
        feedback.applySettings(settings)
    }

    func startGame() {
        guard mode == nil else { return }
        prepareRun(settings.tutorialSeen ? .classic : .practice(.capture))
    }

    func startPractice() {
        prepareRun(.practice(.capture))
    }

    func skipPractice() {
        guard case .practice = mode else { return }
        settings.tutorialSeen = true
        prepareRun(.classic)
    }

    func advanceLesson() {
        guard case let .practice(lesson) = mode else { return }
        if state == .results {
            prepareRun(.practice(lesson))
        } else if state == .lessonComplete {
            if let next = Lesson(rawValue: lesson.rawValue + 1) { prepareRun(.practice(next)) }
            else { skipPractice() }
        }
    }

    func restartGame() {
        guard let mode, state == .paused || state == .results else { return }
        prepareRun(mode)
    }

    func showHome() {
        feedback.stopAll()
        scene.resetScene()
        session = nil
        mode = nil
        state = .ready
    }

    func beginTouch(_ id: Int) {
        if session?.beginTouch(id) == true { state = .playing }
    }

    func endTouch(_ id: Int) { session?.endTouch(id) }

    func cancelTouch(_ id: Int) {
        if session?.cancelTouch(id) == true { finishPause() }
    }

    func pauseGame(_ reason: PauseReason) {
        session?.pauseRun(reason)
        finishPause()
    }

    func armResume() {
        session?.armResume()
        syncState()
        scene.resetClock()
    }

    func advanceFrame(_ elapsed: Double) -> [GameEvent] {
        guard let events = session?.advanceFrame(elapsed), let core = session?.core else { return [] }
        let priorState = state
        syncState()
        if priorState != .paused && state == .paused { feedback.stopAll() }
        let nextHUD = GameHUD(score: core.stats.score, stage: core.stage, locks: core.locks, charging: core.charging, recovering: core.recovery > 0, danger: core.ring >= 250)
        if nextHUD != hud { hud = nextHUD }
        for event in events {
            feedback.consumeEvent(event)
            if case let .defeat(focus) = event, mode == .classic {
                let run = RunRecord(rulesVersion: ArenaRules.version, stats: core.stats, cause: focus.cause)
                newBest = records.recordRun(run)
                storage.saveRecords(records)
                result = run
                #if DEBUG
                if let replay = session?.replay { storage.saveReplay(replay) }
                #endif
            } else if case .defeat = event {
                practiceFailed = true
            }
        }
        return events
    }

    private func syncState() {
        if let next = session?.state, next != state { state = next }
    }

    private func finishPause() {
        syncState()
        scene.resetClock()
        feedback.stopAll()
    }

    private func prepareRun(_ mode: GameMode) {
        feedback.prepareSounds()
        feedback.stopAll()
        scene.resetScene()
        session = GameSession(mode: mode, seed: UInt64.random(in: .min ... .max))
        self.mode = mode
        result = nil
        newBest = false
        practiceFailed = false
        hud = GameHUD()
        state = .ready
    }
}
