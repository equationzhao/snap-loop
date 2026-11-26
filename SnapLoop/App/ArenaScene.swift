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
private func makeTexture(_ size: CGSize, draw: (CGContext) -> Void) -> SKTexture {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 2
    let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
        let context = renderer.cgContext
        context.translateBy(x: size.width / 2, y: size.height / 2)
        context.scaleBy(x: 1, y: -1)
        draw(context)
    }
    return SKTexture(image: image)
}

@MainActor
private final class ChargeRingNode: SKSpriteNode {
    private var previousRadius = -1.0
    private var previousAppearance: SIMD3<Float>?

    init() {
        super.init(texture: nil, color: .white, size: .zero)
        let ringShader = SKShader(source: """
            void main() {
                float radius = a_radius;
                vec2 p = (v_tex_coord - vec2(0.5)) * (2.0 * (radius + 16.0));
                float distance = length(p) - radius;
                float halfWidth = a_appearance.x;
                float edge = abs(distance) - halfWidth;
                float outline = 1.0 - smoothstep(-0.6, 0.8, edge);
                float fill = 1.0 - smoothstep(-0.6, 0.8, distance);
                float glow = (1.0 - smoothstep(0.0, 6.0, edge)) * a_appearance.y * 0.54;
                float opacity = max(outline, max(glow, fill * (0.05 + 0.07 * a_appearance.y)));
                if (distance > 2.0 && distance < 14.0) {
                    float tick = 0.52359878;
                    float angle = atan(p.y, p.x);
                    float mark = floor(angle / tick + 0.5);
                    float width = abs(sin(angle - mark * tick)) * (radius + distance);
                    float end = mod(abs(mark), 3.0) < 0.5 ? 13.0 : 7.0;
                    float lengthMask = smoothstep(2.0, 3.0, distance) * (1.0 - smoothstep(end, end + 1.0, distance));
                    opacity = max(opacity, lengthMask * (1.0 - smoothstep(0.55, 1.55, width)));
                }
                vec3 color = a_appearance.z > 1.5 ? vec3(1.0, 0.8, 0.4) :
                    (a_appearance.z > 0.5 ? vec3(1.0, 0.33, 0.44) : vec3(0.53, 1.0, 0.87));
                gl_FragColor = vec4(color * opacity, opacity);
            }
            """)
        ringShader.attributes = [
            SKAttribute(name: "a_radius", type: .float),
            SKAttribute(name: "a_appearance", type: .vectorFloat3),
        ]
        shader = ringShader
        isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    func updateRing(radius: Double, lineWidth: Double, flash: Double, color: Float) {
        if previousRadius != radius {
            previousRadius = radius
            let diameter = (radius + 16) * 2
            size = CGSize(width: diameter, height: diameter)
            setValue(SKAttributeValue(float: Float(radius)), forAttribute: "a_radius")
        }
        let appearance = SIMD3<Float>(Float(lineWidth * 0.5), Float(flash), color)
        if previousAppearance != appearance {
            previousAppearance = appearance
            setValue(SKAttributeValue(vectorFloat3: appearance), forAttribute: "a_appearance")
        }
    }
}

@MainActor
private final class ActorNode: SKSpriteNode {
    let glow: SKSpriteNode
    let detail = SKSpriteNode()

    init(texture: SKTexture, glowTexture: SKTexture, side: CGFloat) {
        let size = CGSize(width: side, height: side)
        glow = SKSpriteNode(texture: glowTexture, size: size)
        super.init(texture: texture, color: .white, size: size)
        glow.zPosition = -0.5
        addChild(glow)
        detail.zPosition = 0.5
        detail.size = size
        addChild(detail)
    }

    required init?(coder: NSCoder) { nil }

    func updateStyle(_ nextTexture: SKTexture, flash: Double) {
        if texture !== nextTexture { texture = nextTexture }
        if glow.alpha != flash { glow.alpha = flash }
        let showGlow = flash > 0
        if glow.isHidden == showGlow { glow.isHidden = !showGlow }
    }
}

@MainActor
private struct ActorArtwork {
    static let side: CGFloat = 70
    let normal: SKTexture
    let contrast: SKTexture
    let highlighted: SKTexture
    let glow: SKTexture

    init(path: CGPath, color: UIColor, fill: CGFloat, highlightedFill: CGFloat, width: CGFloat, highlightedWidth: CGFloat) {
        let size = CGSize(width: Self.side, height: Self.side)
        func bakeBody(fill: CGFloat, width: CGFloat) -> SKTexture {
            makeTexture(size) { context in
                context.setLineJoin(.round)
                context.setStrokeColor(color.cgColor)
                context.setFillColor(color.withAlphaComponent(fill).cgColor)
                context.setLineWidth(width)
                context.addPath(path)
                context.drawPath(using: .fillStroke)
            }
        }
        normal = bakeBody(fill: fill, width: width)
        contrast = fill < 0.36 ? bakeBody(fill: 0.36, width: width) : normal
        highlighted = bakeBody(fill: highlightedFill, width: highlightedWidth)
        glow = makeTexture(size) { context in
            context.setLineJoin(.round)
            context.setShadow(offset: .zero, blur: 4, color: color.withAlphaComponent(0.85).cgColor)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(3)
            context.addPath(path)
            context.strokePath()
        }
    }

    func makeNode() -> ActorNode {
        ActorNode(texture: normal, glowTexture: glow, side: Self.side)
    }
}

@MainActor
final class ArenaScene: SKScene {
    private weak var model: GameModel?
    private let arena = SKNode()
    private let content = SKNode()
    private let effects = SKNode()
    private let boundary = SKShapeNode()
    private let ring = ChargeRingNode()
    private let coreShape = SKShapeNode()
    private let centerAccent = SKShapeNode()
    private var enemyNodes: [Int: ActorNode] = [:]
    private var hazardNodes: [Int: ActorNode] = [:]
    private var warningNodes: [Int: SKShapeNode] = [:]
    private var lastTime: TimeInterval?
    private var cosmeticRandom = GameplayRandom(seed: 93051)
    private var shake = 0.0
    private var renderedTick = -1
    private var renderedStyle: RenderStyle?
    private var previousPalette: Palette?

    private struct RenderStyle: Equatable {
        let flash: Double
        let contrast: Bool
        let reduceMotion: Bool
        let showMarkers: Bool
    }

    private enum RingTint: Float {
        case normal = 0, hazard = 1, cleanse = 2

        var color: UIColor {
            switch self {
            case .normal: aqua
            case .cleanse: gold
            case .hazard: coral
            }
        }
    }

    private struct Palette: Equatable {
        let coreTint: RingTint
        let danger: Bool
        let contrast: Bool
    }

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
        arena.addChild(ring)
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
        let style = RenderStyle(flash: model.settings.flash, contrast: model.highContrast, reduceMotion: model.reduceMotion,
                                showMarkers: model.settings.showMarkers || model.differentiateWithoutColor)
        if renderedTick != core.tick || renderedStyle != style || !events.isEmpty {
            renderArena(core, locks: model.hud.locks, style: style)
            renderedTick = core.tick
            renderedStyle = style
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
        let field = SKSpriteNode(texture: Self.fieldTexture, size: CGSize(width: 710, height: 710))
        field.zPosition = -1
        arena.addChild(field)
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

    private static let fieldTexture = makeTexture(CGSize(width: 710, height: 710)) { context in
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
        context.setStrokeColor(aqua.withAlphaComponent(0.12).cgColor)
        context.setLineWidth(0.75)
        context.addPath(grid)
        context.strokePath()
        for radius in [72.0, 144, 216, 280, 326, 350] {
            context.setStrokeColor(aqua.withAlphaComponent(radius == 326 ? 0.28 : 0.15).cgColor)
            context.setLineWidth(radius == 326 ? 2 : 1)
            context.addPath(drawCircle(radius))
            context.strokePath()
        }
        let scale = CGMutablePath()
        for tick in 0..<96 {
            let angle = Double(tick) * .pi / 48
            scale.move(to: ArenaPoint(radius: tick.isMultiple(of: 8) ? 336 : 344, angle: angle).cg)
            scale.addLine(to: ArenaPoint(radius: 352, angle: angle).cg)
        }
        context.setStrokeColor(aqua.withAlphaComponent(0.32).cgColor)
        context.setLineWidth(1.5)
        context.addPath(scale)
        context.strokePath()
    }

    private func renderArena(_ core: GameCore, locks: LockState, style: RenderStyle) {
        let contrast = style.contrast
        let flash = style.flash
        let reduceMotion = style.reduceMotion
        let danger = core.ring >= 250
        let tint: RingTint = locks.canCleanse ? .cleanse : (danger || locks.hazards > 0 ? .hazard : .normal)
        let palette = Palette(coreTint: core.death == nil ? tint : .hazard, danger: danger, contrast: contrast)
        if palette != previousPalette {
            previousPalette = palette
            boundary.strokeColor = coral.withAlphaComponent(danger ? 0.92 : (contrast ? 0.65 : 0.32))
            boundary.lineWidth = danger ? 3 : 1.8
            coreShape.strokeColor = palette.coreTint.color
            centerAccent.fillColor = palette.coreTint.color
        }
        centerAccent.zRotation = reduceMotion ? 0 : Double(core.tick) * 0.006
        if ring.isHidden == core.charging { ring.isHidden = !core.charging }
        if core.charging {
            ring.updateRing(radius: core.ring, lineWidth: locks.canCleanse || contrast ? 5 : 3, flash: flash, color: tint.rawValue)
        }
        for enemy in core.enemies {
            let artwork = Self.enemyArtwork[enemy.kind]!
            let node = enemyNodes[enemy.id] ?? addEnemy(enemy, artwork: artwork)
            node.position = enemy.point.cg
            node.zRotation = enemy.kind == .lancer ? enemy.angle + .pi / 2 : (reduceMotion ? 0 : Double(core.tick) * 0.018 + enemy.angle)
            let captured = core.charging && ArenaRules.capturesEnemy(enemy, radius: core.ring)
            node.updateStyle(captured ? artwork.highlighted : (contrast ? artwork.contrast : artwork.normal),
                             flash: flash * (captured ? 0.86 : 0.30))
            node.detail.isHidden = !(captured || style.showMarkers)
        }
        if enemyNodes.count != core.enemies.count {
            let active = Set(core.enemies.map(\.id))
            for id in enemyNodes.keys where !active.contains(id) { enemyNodes.removeValue(forKey: id)?.removeFromParent() }
        }
        for hazard in core.hazards {
            let artwork = hazard.isComet ? Self.cometArtwork : Self.mineArtwork
            let node = hazardNodes[hazard.id] ?? addHazard(hazard, artwork: artwork)
            node.position = hazard.point.cg
            node.alpha = hazard.armed ? 1 : 0.25
            let contained = core.charging && ArenaRules.containsHazard(hazard, radius: core.ring)
            node.updateStyle(contained ? artwork.highlighted : artwork.normal, flash: flash * (contained ? 1 : 0.45))
            if !hazard.isComet {
                let frame = Int((hazard.fuse / hazard.total * Double(Self.fuseSteps)).rounded())
                let texture = Self.fuseTextures[max(0, min(Self.fuseSteps, frame))]
                if node.detail.texture !== texture { node.detail.texture = texture }
            }
        }
        if hazardNodes.count != core.hazards.count {
            let active = Set(core.hazards.map(\.id))
            for id in hazardNodes.keys where !active.contains(id) { hazardNodes.removeValue(forKey: id)?.removeFromParent() }
        }
        for warning in core.warnings {
            let node = warningNodes[warning.id] ?? addWarning(warning)
            node.alpha = 0.4 + 0.45 * (1 - max(0, warning.countdown / 0.95))
        }
        if warningNodes.count != core.warnings.count {
            let active = Set(core.warnings.map(\.id))
            for id in warningNodes.keys where !active.contains(id) { warningNodes.removeValue(forKey: id)?.removeFromParent() }
        }
    }

    private static func enemyColor(_ kind: EnemyKind) -> UIColor {
        switch kind {
        case .drifter, .starter: aqua
        case .lancer: gold
        case .spiral: UIColor(red: 0.76, green: 0.59, blue: 1, alpha: 1)
        case .splitter, .shard: .systemGreen
        case .charger: .white
        }
    }

    private static let enemyArtwork = Dictionary(uniqueKeysWithValues: EnemyKind.allCases.map { kind in
        let path: CGPath = switch kind {
        case .drifter, .starter: drawPolygon(4, radius: 18)
        case .lancer: drawPolygon(3, radius: 23)
        case .spiral: drawPolygon(4, radius: 23, phase: .pi / 4, inner: 8)
        case .splitter: drawPolygon(6, radius: 22)
        case .charger: drawPolygon(5, radius: 21)
        case .shard: drawPolygon(3, radius: 12)
        }
        return (kind, ActorArtwork(path: path, color: enemyColor(kind), fill: 0.22, highlightedFill: 0.72,
                                   width: 2.4, highlightedWidth: 4))
    })

    private static let actorSize = CGSize(width: ActorArtwork.side, height: ActorArtwork.side)
    private static let markerTexture = makeTexture(actorSize) { context in
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.68).cgColor)
        context.setLineWidth(1.5)
        context.addPath(drawCircle(25))
        context.strokePath()
    }
    private static let mineArtwork = bakeHazard(sides: 4)
    private static let cometArtwork = bakeHazard(sides: 6)
    private static let fuseSteps = 32
    private static let fuseTextures = (0...fuseSteps).map { frame in
        makeTexture(actorSize) { context in
            guard frame > 0 else { return }
            context.setLineWidth(1.5)
            context.setStrokeColor(coral.withAlphaComponent(0.66).cgColor)
            let top = CGFloat.pi / 2
            let end = top - 2 * .pi * CGFloat(frame) / CGFloat(fuseSteps)
            context.addArc(center: .zero, radius: 23, startAngle: top, endAngle: end, clockwise: true)
            context.strokePath()
        }
    }

    private static func bakeHazard(sides: Int) -> ActorArtwork {
        ActorArtwork(path: drawPolygon(sides, radius: 20, phase: .pi / 4, inner: 8), color: coral,
                     fill: 0.42, highlightedFill: 0.42, width: 2.8, highlightedWidth: 5)
    }

    private func addEnemy(_ enemy: Enemy, artwork: ActorArtwork) -> ActorNode {
        let node = artwork.makeNode()
        node.detail.texture = Self.markerTexture
        node.detail.color = Self.enemyColor(enemy.kind)
        node.detail.colorBlendFactor = 1
        content.addChild(node)
        enemyNodes[enemy.id] = node
        return node
    }

    private func addHazard(_ hazard: Hazard, artwork: ActorArtwork) -> ActorNode {
        let node = artwork.makeNode()
        node.zPosition = 3
        node.detail.isHidden = hazard.isComet
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
        let available = 90 - effects.children.count
        guard available > 0 else { return }
        for _ in 0..<min(available, Int(3 + strength * 5)) {
            let spark = SKSpriteNode(color: color, size: CGSize(width: 6, height: 2.6))
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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let screen = window?.windowScene?.screen {
            preferredFramesPerSecond = min(120, screen.maximumFramesPerSecond)
        }
    }

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
        for touch in touches {
            if let id = gestures.removeValue(forKey: ObjectIdentifier(touch)) { model?.cancelTouch(id) }
        }
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
