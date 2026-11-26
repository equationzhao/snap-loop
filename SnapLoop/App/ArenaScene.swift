import SpriteKit
import SwiftUI

private let ink = UIColor(red: 0.025, green: 0.030, blue: 0.067, alpha: 1)
private let aqua = UIColor(red: 0.53, green: 1, blue: 0.87, alpha: 1)
private let coral = UIColor(red: 1, green: 0.33, blue: 0.44, alpha: 1)
private let gold = UIColor(red: 1, green: 0.80, blue: 0.40, alpha: 1)

private extension ArenaPoint {
    var cg: CGPoint { CGPoint(x: x, y: y) }
}

private func drawPolygon(_ sides: Int, radius: CGFloat, phase: CGFloat = .pi / 2, inner: CGFloat? = nil) -> CGPath {
    let path = CGMutablePath()
    let count = inner == nil ? sides : sides * 2
    for index in 0..<count {
        let angle = phase + 2 * .pi * CGFloat(index) / CGFloat(count)
        let length = index.isMultiple(of: 2) ? radius : (inner ?? radius)
        let point = CGPoint(x: cos(angle) * length, y: sin(angle) * length)
        if index == 0 { path.move(to: point) }
        else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

private func drawCircle(_ radius: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
}

@MainActor
final class ArenaScene: SKScene {
    private weak var model: GameModel?
    private let arena = SKNode()
    private let content = SKNode()
    private let effects = SKNode()
    private let boundary = SKShapeNode()
    private let ring = SKShapeNode()
    private let ringMarks = SKShapeNode()
    private let coreShape = SKShapeNode()
    private let centerAccent = SKShapeNode()
    private var enemyNodes: [Int: SKShapeNode] = [:]
    private var hazardNodes: [Int: SKShapeNode] = [:]
    private var warningNodes: [Int: SKShapeNode] = [:]
    private var lastTime: TimeInterval?
    private var cosmeticRandom = GameplayRandom(seed: 93051)
    private var shake = 0.0
    private var previousRadius = -1.0
    private var renderedTick = -1

    init(model: GameModel) {
        self.model = model
        super.init(size: CGSize(width: 390, height: 844))
        scaleMode = .resizeFill
        backgroundColor = ink
        addChild(arena)
        drawField()
        arena.addChild(content)
        arena.addChild(effects)
        effects.zPosition = 40
        ring.zPosition = 20
        ringMarks.zPosition = 21
        arena.addChild(ring)
        arena.addChild(ringMarks)
        placeArena()
    }

    required init?(coder: NSCoder) { nil }

    override func didChangeSize(_ oldSize: CGSize) { placeArena() }

    func resetClock() { lastTime = nil }

    func resetScene() {
        resetClock()
        content.removeAllChildren()
        effects.removeAllChildren()
        enemyNodes.removeAll()
        hazardNodes.removeAll()
        warningNodes.removeAll()
        shake = 0
        renderedTick = -1
        placeArena()
    }

    override func update(_ currentTime: TimeInterval) {
        let elapsed = lastTime.map { currentTime - $0 } ?? 0
        lastTime = currentTime
        guard let model, model.mode != nil else { return }
        let events = model.advanceFrame(elapsed)
        guard let core = model.core else { return }
        let frozen = model.state == .paused || model.state == .resumeArmed
        effects.isPaused = frozen
        if renderedTick != core.tick || !events.isEmpty || core.charging {
            renderArena(core, model: model)
            renderedTick = core.tick
        }
        for event in events {
            switch event {
            case let .snap(effect): drawSnap(effect, model: model)
            case let .defeat(focus): drawDefeat(focus, model: model)
            case .lessonComplete where model.mode == .practice(.overload):
                drawDefeat(DeathFocus(cause: .overload, point: ArenaPoint(x: 0, y: core.ring), radius: core.ring), model: model)
            default: break
            }
        }
        if !frozen && shake > 0 {
            shake = max(0, shake - min(elapsed, 0.04) * 36)
            let offset = CGPoint(x: (cosmeticRandom.nextUnit() - 0.5) * shake, y: (cosmeticRandom.nextUnit() - 0.5) * shake)
            placeArena(offset)
        }
    }

    private func placeArena(_ offset: CGPoint = .zero) {
        arena.setScale(max(0.01, min((size.width - 22) / 750, (size.height * 0.61) / 750)))
        arena.position = CGPoint(x: size.width * 0.5 + offset.x, y: size.height * 0.575 + offset.y)
    }

    private func drawField() {
        let grid = CGMutablePath()
        for tick in stride(from: -350, through: 350, by: 25) {
            if tick != 0 {
                let length = sqrt(350 * 350 - Double(tick * tick))
                grid.move(to: CGPoint(x: Double(tick), y: -length))
                grid.addLine(to: CGPoint(x: Double(tick), y: length))
                grid.move(to: CGPoint(x: -length, y: Double(tick)))
                grid.addLine(to: CGPoint(x: length, y: Double(tick)))
            }
        }
        let gridNode = SKShapeNode(path: grid)
        gridNode.strokeColor = aqua.withAlphaComponent(0.12)
        gridNode.lineWidth = 0.75
        arena.addChild(gridNode)
        for radius in [72.0, 144, 216, 280, 326, 350] {
            let guide = SKShapeNode(path: drawCircle(radius))
            guide.strokeColor = aqua.withAlphaComponent(radius == 326 ? 0.28 : 0.15)
            guide.lineWidth = radius == 326 ? 2 : 1
            arena.addChild(guide)
        }
        let scale = CGMutablePath()
        for tick in 0..<96 {
            let angle = Double(tick) * .pi / 48
            scale.move(to: ArenaPoint(radius: tick.isMultiple(of: 8) ? 336 : 344, angle: angle).cg)
            scale.addLine(to: ArenaPoint(radius: 352, angle: angle).cg)
        }
        let scaleNode = SKShapeNode(path: scale)
        scaleNode.strokeColor = aqua.withAlphaComponent(0.32)
        scaleNode.lineWidth = 1.5
        arena.addChild(scaleNode)
        boundary.path = drawCircle(ArenaRules.maximum)
        boundary.lineWidth = 1.8
        arena.addChild(boundary)
        coreShape.path = drawPolygon(6, radius: 21)
        coreShape.lineWidth = 3
        coreShape.glowWidth = 3
        coreShape.strokeColor = aqua
        coreShape.fillColor = ink
        coreShape.zPosition = 5
        arena.addChild(coreShape)
        centerAccent.path = drawPolygon(3, radius: 9)
        centerAccent.fillColor = aqua
        centerAccent.strokeColor = .clear
        centerAccent.zPosition = 6
        arena.addChild(centerAccent)
    }

    private func renderArena(_ core: GameCore, model: GameModel) {
        let contrast = model.highContrast
        let danger = core.ring >= 250
        let locks = core.locks
        let color = locks.canCleanse ? gold : ((danger || locks.hazards > 0) ? coral : aqua)
        boundary.strokeColor = coral.withAlphaComponent(danger ? 0.92 : (contrast ? 0.65 : 0.32))
        boundary.lineWidth = danger ? 3 : 1.8
        coreShape.strokeColor = core.death == nil ? color : coral
        centerAccent.fillColor = core.death == nil ? color : coral
        centerAccent.zRotation = model.reduceMotion ? 0 : Double(core.tick) * 0.006
        ring.isHidden = !core.charging
        ringMarks.isHidden = !core.charging
        if core.charging {
            if previousRadius != core.ring {
                previousRadius = core.ring
                ring.path = drawCircle(core.ring)
                let marks = CGMutablePath()
                for index in 0..<12 {
                    let angle = Double(index) * .pi / 6
                    marks.move(to: ArenaPoint(radius: core.ring + 3, angle: angle).cg)
                    marks.addLine(to: ArenaPoint(radius: core.ring + (index.isMultiple(of: 3) ? 13 : 7), angle: angle).cg)
                }
                ringMarks.path = marks
            }
            ring.strokeColor = color
            ring.glowWidth = 4 * model.settings.flash
            ring.fillColor = color.withAlphaComponent(0.05 + 0.07 * model.settings.flash)
            ring.lineWidth = locks.canCleanse || contrast ? 5 : 3
            ringMarks.strokeColor = color
            ringMarks.lineWidth = 2.2
        }
        let activeEnemies = Set(core.enemies.map(\.id))
        for id in enemyNodes.keys where !activeEnemies.contains(id) { enemyNodes.removeValue(forKey: id)?.removeFromParent() }
        for enemy in core.enemies {
            let node = enemyNodes[enemy.id] ?? addEnemy(enemy)
            node.position = enemy.point.cg
            node.zRotation = enemy.kind == .lancer ? enemy.angle + .pi / 2 : (model.reduceMotion ? 0 : Double(core.tick) * 0.018 + enemy.angle)
            let captured = core.charging && enemy.radius <= core.ring + ArenaRules.captureGrace
            let color = enemyColor(enemy.kind)
            node.fillColor = captured ? color.withAlphaComponent(0.72) : color.withAlphaComponent(contrast ? 0.36 : 0.22)
            node.lineWidth = captured ? 4 : 2.4
            node.glowWidth = model.settings.flash * (captured ? 3.4 : 1.0)
            node.childNode(withName: "marker")?.isHidden = !(captured || model.settings.showMarkers || model.differentiateWithoutColor)
        }
        let activeMines = Set(core.hazards.map(\.id))
        for id in hazardNodes.keys where !activeMines.contains(id) { hazardNodes.removeValue(forKey: id)?.removeFromParent() }
        for hazard in core.hazards {
            let node = hazardNodes[hazard.id] ?? addHazard(hazard)
            node.position = hazard.point.cg
            node.alpha = hazard.armed ? 1 : 0.25
            let contained = core.charging && hazard.armed && hazard.radius <= core.ring - ArenaRules.mineGrace
            node.lineWidth = contained ? 5 : 2.8
            node.glowWidth = (contained ? 4 : 1.8) * model.settings.flash
            if let fuse = node.childNode(withName: "fuse") as? SKShapeNode {
                let path = CGMutablePath()
                path.addArc(center: .zero, radius: 23, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * hazard.fuse / hazard.total, clockwise: true)
                fuse.path = path
            }
        }
        let activeWarnings = Set(core.warnings.map(\.id))
        for id in warningNodes.keys where !activeWarnings.contains(id) { warningNodes.removeValue(forKey: id)?.removeFromParent() }
        for warning in core.warnings {
            let node = warningNodes[warning.id] ?? addWarning(warning)
            node.alpha = 0.4 + 0.45 * (1 - max(0, warning.countdown / 0.95))
        }
    }

    private func enemyColor(_ kind: EnemyKind) -> UIColor {
        switch kind {
        case .drifter, .starter: aqua
        case .lancer: gold
        case .spiral: UIColor(red: 0.76, green: 0.59, blue: 1, alpha: 1)
        case .splitter, .shard: .systemGreen
        case .charger: .white
        }
    }

    private func addEnemy(_ enemy: Enemy) -> SKShapeNode {
        let path: CGPath = switch enemy.kind {
        case .drifter, .starter: drawPolygon(4, radius: 18)
        case .lancer: drawPolygon(3, radius: 23)
        case .spiral: drawPolygon(4, radius: 23, phase: .pi / 4, inner: 8)
        case .splitter: drawPolygon(6, radius: 22)
        case .charger: drawPolygon(5, radius: 21)
        case .shard: drawPolygon(3, radius: 12)
        }
        let node = SKShapeNode(path: path)
        node.strokeColor = enemyColor(enemy.kind)
        let marker = SKShapeNode(path: drawCircle(25))
        marker.strokeColor = enemyColor(enemy.kind).withAlphaComponent(0.68)
        marker.lineWidth = 1.5
        marker.name = "marker"
        node.addChild(marker)
        content.addChild(node)
        enemyNodes[enemy.id] = node
        return node
    }

    private func addHazard(_ hazard: Hazard) -> SKShapeNode {
        let node = SKShapeNode(path: drawPolygon(hazard.isComet ? 6 : 4, radius: 20, phase: .pi / 4, inner: 8))
        node.fillColor = coral.withAlphaComponent(0.42)
        node.strokeColor = coral
        node.zPosition = 3
        if !hazard.isComet {
            let fuse = SKShapeNode()
            fuse.name = "fuse"
            fuse.lineWidth = 1.5
            fuse.strokeColor = coral.withAlphaComponent(0.66)
            node.addChild(fuse)
        }
        content.addChild(node)
        hazardNodes[hazard.id] = node
        return node
    }

    private func addWarning(_ warning: CometWarning) -> SKShapeNode {
        let path = CGMutablePath()
        let dx = (warning.end.x - warning.origin.x) / 30
        let dy = (warning.end.y - warning.origin.y) / 30
        for dash in stride(from: 0.0, to: 30, by: 2) {
            path.move(to: CGPoint(x: warning.origin.x + dx * dash, y: warning.origin.y + dy * dash))
            path.addLine(to: CGPoint(x: warning.origin.x + dx * (dash + 1), y: warning.origin.y + dy * (dash + 1)))
        }
        let node = SKShapeNode(path: path)
        node.strokeColor = coral
        node.lineWidth = 2
        content.addChild(node)
        warningNodes[warning.id] = node
        return node
    }

    private func drawSnap(_ snap: SnapEffect, model: GameModel) {
        let color = snap.isCleanse ? gold : (snap.award == nil ? UIColor.systemGray : aqua)
        let sweep = SKShapeNode(path: drawCircle(snap.radius))
        sweep.strokeColor = color
        sweep.lineWidth = snap.isCleanse ? 10 : 5
        sweep.alpha = 0.56 + model.settings.flash * 0.44
        effects.addChild(sweep)
        let fade = SKAction.fadeOut(withDuration: 0.22)
        let motion = SKAction.scale(to: snap.isCleanse ? 1.24 : 0.38, duration: 0.22)
        sweep.run(.sequence([model.reduceMotion ? fade : .group([motion, fade]), .removeFromParent()]))
        if model.settings.shake && !model.reduceMotion && snap.award != nil { shake = snap.isCleanse ? 7 : 3 }
        if !model.reduceMotion && model.settings.flash > 0 {
            for point in snap.targets.prefix(12) { drawBurst(at: point.cg, color: color, strength: model.settings.flash) }
        }
        guard let award = snap.award, let point = snap.targets.first else { return }
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.fontSize = 32
        label.fontColor = color
        label.text = "+\(award.total)"
        label.position = CGPoint(x: max(-220, min(220, point.x)), y: max(-250, min(272, point.y + 43)))
        effects.addChild(label)
        let float = SKAction.moveBy(x: 0, y: model.reduceMotion ? 0 : 35, duration: 0.55)
        label.run(.sequence([.group([float, .fadeOut(withDuration: 0.55)]), .removeFromParent()]))
    }

    private func drawBurst(at point: CGPoint, color: UIColor, strength: Double) {
        guard effects.children.count < 90 else { return }
        for _ in 0..<Int(3 + strength * 5) {
            let spark = SKShapeNode(rectOf: CGSize(width: 6, height: 2.6))
            spark.fillColor = color
            spark.strokeColor = .clear
            spark.position = point
            let angle = cosmeticRandom.nextUnit() * 2 * .pi
            let length = 25 + cosmeticRandom.nextUnit() * 55
            spark.zRotation = angle
            let flight = SKAction.moveBy(x: cos(angle) * length, y: sin(angle) * length, duration: 0.27)
            effects.addChild(spark)
            spark.run(.sequence([.group([flight, .fadeOut(withDuration: 0.27)]), .removeFromParent()]))
        }
    }

    private func drawDefeat(_ focus: DeathFocus, model: GameModel) {
        content.alpha = 1
        let spotlight = SKShapeNode(path: drawCircle(focus.cause == .overload ? ArenaRules.maximum : 31))
        if focus.cause != .overload { spotlight.position = focus.point.cg }
        spotlight.strokeColor = coral
        spotlight.lineWidth = 6
        spotlight.glowWidth = 7 * model.settings.flash
        effects.addChild(spotlight)
        if focus.cause != .overload { drawBurst(at: focus.point.cg, color: coral, strength: model.settings.flash) }
        let arc = SKShapeNode(path: drawCircle(focus.radius))
        arc.strokeColor = coral.withAlphaComponent(0.55)
        arc.lineWidth = 3
        effects.addChild(arc)
    }
}

@MainActor
final class TouchArenaView: SKView {
    weak var model: GameModel?
    private var gestures: [ObjectIdentifier: Int] = [:]
    private var nextTouch = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            nextTouch += 1
            gestures[ObjectIdentifier(touch)] = nextTouch
            model?.beginTouch(nextTouch)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {}

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let id = gestures.removeValue(forKey: ObjectIdentifier(touch)) { model?.endTouch(id) }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        gestures.removeAll()
        model?.pauseGame(.cancellation)
    }
}

struct ArenaView: UIViewRepresentable {
    let model: GameModel

    func makeUIView(context: Context) -> TouchArenaView {
        let view = TouchArenaView()
        view.model = model
        view.backgroundColor = ink
        view.isMultipleTouchEnabled = true
        view.preferredFramesPerSecond = 60
        view.ignoresSiblingOrder = true
        view.presentScene(model.scene)
        return view
    }

    func updateUIView(_ view: TouchArenaView, context: Context) {}

    static func dismantleUIView(_ view: TouchArenaView, coordinator: ()) {
        view.presentScene(nil)
    }
}
