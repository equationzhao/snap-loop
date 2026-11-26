import Testing
@testable import SnapLoopCore

struct GameRulesTests {
    @Test func usesTheSameInclusiveLockAndSnapBoundaries() {
        let inside = Enemy(id: 1, kind: .drifter, angle: 0, radius: 106, speed: 0)
        let outside = Enemy(id: 2, kind: .drifter, angle: 0, radius: 106.001, speed: 0)
        let snap = SnapSelection(
            radius: 100,
            enemies: [inside, outside],
            hazards: [makeMine(3, radius: 94), makeMine(4, radius: 94.001), makeMine(5, radius: 80, armed: false)]
        )
        #expect(snap.enemies.map(\.id) == [1])
        #expect(snap.hazards.map(\.id) == [3])
        #expect(snap.grazesMine)
        #expect(!snap.isCleanse)
    }

    @Test func calculatesAllBonusesIndependently() {
        let enemies = [39.0, 120.0, 281.0].enumerated().map {
            Enemy(id: $0.offset, kind: .drifter, angle: 0, radius: $0.element, speed: 0)
        }
        let snap = SnapSelection(radius: 290, enemies: enemies, hazards: [makeMine(3, radius: 150), makeMine(4, radius: 260), makeMine(5, radius: 292)])
        let award = ScoreRules().calculateAward(snap, radius: 290)
        #expect(award.base == 90)
        #expect(award.bonuses == [.mineBreak: 100, .closeCut: 50, .mineGraze: 40, .fullDraw: 40])
        #expect(award.total == 320)
    }

    @Test func mineKillsBeforeAwardUnlessAllThreeTargetsAreCaptured() {
        var unsafe = GameSession(mode: .practice(.mine), seed: 28)
        _ = unsafe.beginTouch(1)
        advanceFrames(38, in: &unsafe)
        unsafe.endTouch(1)
        advanceFrames(1, in: &unsafe)
        #expect(unsafe.core.death?.cause == .mine(comet: false, locked: 1))
        #expect(unsafe.core.stats.score == 0)

        var safe = GameSession(mode: .practice(.mine), seed: 28)
        _ = safe.beginTouch(1)
        advanceFrames(60, in: &safe)
        #expect(safe.core.locks == LockState(enemies: 3, hazards: 1))
        safe.endTouch(1)
        advanceFrames(1, in: &safe)
        #expect(safe.state == .lessonComplete)
        #expect(safe.core.stats.score == 0)
    }

    @Test func preservesChargeAndIgnoresStaleTouchesAcrossPause() {
        var session = GameSession(mode: .classic, seed: 7)
        advanceFrames(100, in: &session)
        #expect(session.core.tick == 0)
        let accepted1 = session.beginTouch(1)
        #expect(accepted1)
        let accepted2 = session.beginTouch(2)
        #expect(!accepted2)
        advanceFrames(30, in: &session)
        let radius = session.core.ring
        let tick = session.core.tick
        session.pauseRun(.inactive)
        session.endTouch(1)
        session.endTouch(2)
        advanceFrames(240, in: &session)
        #expect(session.state == .paused)
        #expect(session.core.ring == radius)
        #expect(session.core.tick == tick)
        session.armResume()
        advanceFrames(30, in: &session)
        #expect(session.state == .resumeArmed)
        #expect(session.core.ring == radius)
        let accepted3 = session.beginTouch(3)
        #expect(accepted3)
        advanceFrames(1, in: &session)
        #expect(session.core.ring > radius)
        session.endTouch(3)
        advanceFrames(1, in: &session)
        #expect(session.core.ring == ArenaRules.minimum)
        #expect(session.core.recovery > 0)
        #expect(session.replay.entries.map(\.command) == [.press, .detach, .press, .release])
        #expect(session.replay.entries[1].pause == .inactive)
    }

    @Test func emptySnapKeepsOnlyAStillHeldTouchAfterRecovery() {
        var session = GameSession(mode: .classic, seed: 7)
        let accepted1 = session.beginTouch(1)
        #expect(accepted1)
        session.endTouch(1)
        advanceFrames(1, in: &session)
        #expect(session.core.recovery > 0)
        let accepted2 = session.beginTouch(2)
        #expect(accepted2)
        advanceFrames(5, in: &session)
        session.endTouch(2)
        advanceFrames(60, in: &session)
        #expect(!session.core.charging)
        #expect(session.core.recovery == 0)
        let accepted3 = session.beginTouch(3)
        #expect(accepted3)
        session.endTouch(3)
        advanceFrames(1, in: &session)
        let accepted4 = session.beginTouch(4)
        #expect(accepted4)
        advanceFrames(45, in: &session)
        #expect(session.core.charging)
        #expect(session.core.ring > ArenaRules.minimum)
    }

    @Test func reproducesSeededClassicRunAtBothRenderRates() throws {
        func playRun(fps: Int) -> GameSession {
            var run = GameSession(mode: .classic, seed: 75423)
            _ = run.beginTouch(1)
            for _ in 0..<(6 * fps / 5) { _ = run.advanceFrame(1 / Double(fps)) }
            run.endTouch(1)
            for _ in 0..<(12 * fps) { _ = run.advanceFrame(1 / Double(fps)) }
            return run
        }
        let standard = playRun(fps: 60)
        let fast = playRun(fps: 120)
        let reproduced = try #require(standard.replay.reproduceRun())
        #expect(standard.core.stats.score > 0)
        #expect(standard.core.death?.cause != nil)
        #expect(standard.core.stats == fast.core.stats)
        #expect(standard.core.death == fast.core.death)
        #expect(standard.core.death == reproduced.death)
        #expect(standard.core.stats == reproduced.stats)
        #expect(standard.core.tick == reproduced.tick)
    }

    @Test func cancellationAfterDeathKeepsResults() {
        var session = GameSession(mode: .classic, seed: 7)
        _ = session.beginTouch(1)
        advanceFrames(250, in: &session)
        #expect(session.core.death?.cause == .overload)
        #expect(session.state == .results)
        _ = session.cancelTouch(1)
        session.armResume()
        session.endTouch(1)
        #expect(session.state == .results)
    }

    @Test func onlyTheCurrentTouchCanCancelTheRun() {
        var session = GameSession(mode: .classic, seed: 8)
        _ = session.beginTouch(1)
        advanceFrames(20, in: &session)
        _ = session.cancelTouch(1)
        #expect(session.state == .paused)
        session.armResume()
        _ = session.beginTouch(2)
        advanceFrames(20, in: &session)
        _ = session.cancelTouch(1)
        #expect(session.state == .playing)
        #expect(session.core.charging)
    }

    @Test func queuesReleaseDuringHitStopUntilTheFirstPlayableStep() {
        var session = GameSession(mode: .classic, seed: 75)
        _ = session.beginTouch(1)
        advanceFrames(144, in: &session)
        session.endTouch(1)
        advanceFrames(1, in: &session)
        #expect(session.core.stats.kills == 1)
        #expect(session.core.hitStop > 0)
        _ = session.beginTouch(2)
        session.endTouch(2)
        advanceFrames(1, in: &session)
        #expect(session.core.recovery == 0)
        advanceFrames(9, in: &session)
        #expect(session.core.recovery > 0)
        #expect(session.replay.entries.map(\.command) == [.press, .release, .press, .release])
    }

    private func makeMine(_ id: Int, radius: Double, armed: Bool = true) -> Hazard {
        Hazard(id: id, motion: .ember(angle: 0, target: radius, radius: radius), point: ArenaPoint(x: radius, y: 0), fuse: 1, total: 1, armed: armed)
    }

    private func advanceFrames(_ count: Int, in session: inout GameSession) {
        for _ in 0..<count { _ = session.advanceFrame(1.0 / 120) }
    }
}
