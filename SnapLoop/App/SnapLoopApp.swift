import AVFoundation
import SwiftUI

private let night = Color(red: 0.025, green: 0.030, blue: 0.067)
private let mint = Color(red: 0.53, green: 1, blue: 0.87)
private let yellow = Color(red: 1, green: 0.80, blue: 0.40)
private let red = Color(red: 1, green: 0.39, blue: 0.48)

func tr(_ key: String) -> String { String(localized: String.LocalizationValue(key)) }

private func timeLabel(_ seconds: Double) -> String {
    let value = Int(seconds)
    return "\(value / 60):\(String(format: "%02d", value % 60))"
}

private extension EnemyKind {
    var label: String {
        switch self {
        case .drifter: tr("巡游者")
        case .lancer: tr("突刺者")
        case .spiral: tr("旋星")
        case .splitter: tr("分裂者")
        case .charger: tr("脉冲者")
        case .shard: tr("碎晶")
        case .starter: tr("训练晶核")
        }
    }
}

private extension Defeat {
    var title: String {
        switch self {
        case .core: tr("核心失守")
        case .mine: tr("红雷引爆")
        case .overload: tr("扩环过载")
        }
    }

    var detail: String {
        switch self {
        case let .core(kind): String(format: tr("%@ 击中了核心。"), kind.label)
        case let .mine(comet, locked):
            String(format: tr("瞬斩碰到%@，仅锁定 %d 个敌人。"), comet ? tr("流火孤雷") : tr("红雷"), locked)
        case .overload: tr("攻击环触及过载边界。")
        }
    }
}

@main
struct SnapLoopApp: App {
    var body: some Scene { WindowGroup { RootView() } }
}

private enum Panel: String, Identifiable {
    case records, settings
    var id: Self { self }
}

struct RootView: View {
    @State private var model = GameModel()
    @State private var panel: Panel?
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if model.mode == nil {
                HomeView(best: model.records.bestScore, start: model.startGame, records: { panel = .records }, settings: { panel = .settings })
            } else {
                BattleView(model: model, showSettings: { panel = .settings })
            }
        }
        .sheet(item: $panel) { item in
            NavigationStack {
                switch item {
                case .records: RecordsView(records: model.records)
                case .settings:
                    SettingsView(model: model, startPractice: {
                        panel = nil
                        model.startPractice()
                    }, canStartPractice: model.mode == nil)
                }
            }
        }
        .onChange(of: phase) { _, next in if next != .active { model.pauseGame(.inactive) } }
        .onChange(of: reduceMotion, initial: true) { _, next in model.reduceMotion = next }
        .onChange(of: contrast, initial: true) { _, next in model.highContrast = next == .increased }
        .onChange(of: differentiateWithoutColor, initial: true) { _, next in model.differentiateWithoutColor = next }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            if notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt == AVAudioSession.InterruptionType.began.rawValue {
                model.pauseGame(.audio)
            }
        }
    }
}

private struct HomeView: View {
    let best: Int
    let start: () -> Void
    let records: () -> Void
    let settings: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 12) {
                    Text(tr("瞬环"))
                        .font(.system(size: 62, weight: .heavy, design: .default))
                        .tracking(8)
                        .padding(.leading, 8)
                        .accessibilityAddTraits(.isHeader)
                    Text("S N A P   L O O P")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundStyle(mint)
                        .accessibilityHidden(true)
                    OrbitArtwork()
                        .frame(height: min(322, max(142, geometry.size.height - 390)))
                        .accessibilityHidden(true)
                    VStack(spacing: 7) {
                        Text(tr("按住扩环，松手瞬斩"))
                            .font(.title3.weight(.semibold))
                        Text(String(format: tr("个人最佳  %@"), best.formatted()))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 18)
                    PrimaryButton(title: tr("开始游戏"), icon: "play.fill", action: start)
                        .accessibilityIdentifier("start-game")
                    HStack(spacing: 12) {
                        SecondaryButton(title: tr("纪录"), icon: "chart.bar.xaxis", action: records)
                        SecondaryButton(title: tr("设置"), icon: "gearshape", action: settings)
                    }
                }
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: 460)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(night.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }
}

private struct OrbitArtwork: View {
    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 300
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            func point(_ radius: Double, _ angle: Double) -> CGPoint {
                CGPoint(x: center.x + cos(angle) * radius * unit, y: center.y + sin(angle) * radius * unit)
            }
            func disk(_ radius: Double) -> Path {
                let r = radius * unit
                return Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
            }
            context.fill(disk(150), with: .radialGradient(Gradient(colors: [mint.opacity(0.18), mint.opacity(0.01), .clear]), center: center, startRadius: 5, endRadius: 150 * unit))
            for radius in [32.0, 57, 80, 111, 137, 146] {
                context.stroke(disk(radius), with: .color(mint.opacity(radius == 111 ? 0.55 : 0.20)), style: StrokeStyle(lineWidth: radius == 111 ? 1.6 : 0.7, dash: radius == 137 ? [2, 4] : []))
            }
            var markings = Path()
            for step in 0..<72 {
                let angle = .pi * Double(step) / 36
                markings.move(to: point(step.isMultiple(of: 6) ? 127 : 133, angle))
                markings.addLine(to: point(137, angle))
            }
            context.stroke(markings, with: .color(mint.opacity(0.45)), lineWidth: 0.7)
            for (angle, radius, tint) in [(-0.87, 111.0, mint), (2.34, 111, mint), (3.59, 80, yellow), (0.95, 137, red)] {
                let jewel = point(radius, angle)
                let d = 9 * unit
                let diamond = Path { path in
                    path.move(to: CGPoint(x: jewel.x, y: jewel.y - d))
                    path.addLine(to: CGPoint(x: jewel.x + d, y: jewel.y))
                    path.addLine(to: CGPoint(x: jewel.x, y: jewel.y + d))
                    path.addLine(to: CGPoint(x: jewel.x - d, y: jewel.y))
                    path.closeSubpath()
                }
                context.fill(diamond, with: .color(tint.opacity(0.35)))
                context.stroke(diamond, with: .color(tint), lineWidth: 1.8)
            }
            let crystal = Path { path in
                path.move(to: point(32, -.pi / 2))
                path.addLine(to: point(30, .pi / 7))
                path.addLine(to: point(28, .pi * 0.79))
                path.closeSubpath()
            }
            context.fill(crystal, with: .linearGradient(Gradient(colors: [mint, mint.opacity(0.22)]), startPoint: point(28, -.pi / 2), endPoint: point(28, .pi / 2)))
        }
    }
}

private struct BattleView: View {
    let model: GameModel
    let showSettings: () -> Void

    private var isMenu: Bool {
        model.state == .paused || model.state == .results || model.state == .lessonComplete
    }

    var body: some View {
        ZStack {
            ArenaView(model: model)
                .ignoresSafeArea()
                .accessibilityHidden(true)
                .allowsHitTesting(!isMenu && model.state != .dead)
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                if !isMenu && model.state != .dead { hintBar }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 12)
            if isMenu { actionOverlay }
        }
        .background(night.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if case let .practice(lesson) = model.mode {
                    Text(tr("训练"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(mint)
                    Text("\(lesson.rawValue + 1) / \(Lesson.allCases.count)")
                        .font(.system(.title, design: .monospaced, weight: .semibold))
                } else {
                    Text(tr("得分"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(model.hud.score.formatted())
                        .font(.system(.largeTitle, design: .monospaced, weight: .semibold))
                        .monospacedDigit()
                }
            }
            .allowsHitTesting(false)
            Spacer()
            VStack(alignment: .trailing) {
                if model.mode == .classic {
                    Text([tr("脉冲初醒"), tr("疾影逼近"), tr("旋星流火"), tr("双生裂变"), tr("极夜无双")][model.hud.stage])
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(mint)
                        .allowsHitTesting(false)
                }
                if model.state == .playing || model.state == .resumeArmed {
                    Button(action: { model.pauseGame(.player) }) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(tr("暂停"))
                    .accessibilityIdentifier("pause-game")
                }
            }
        }
    }

    private var hintBar: some View {
        VStack(spacing: 9) {
            if model.hud.charging && model.state == .playing {
                HStack(spacing: 16) {
                    Label("×\(model.hud.locks.enemies)", systemImage: model.hud.locks.canCleanse ? "sparkle" : "scope")
                        .foregroundStyle(model.hud.locks.canCleanse ? yellow : mint)
                        .accessibilityLabel(String(format: tr("已锁定 %d 个敌人"), model.hud.locks.enemies))
                    if model.hud.locks.hazards > 0 {
                        Label("×\(model.hud.locks.hazards)", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(red)
                            .accessibilityLabel(String(format: tr("环内有 %d 颗红雷"), model.hud.locks.hazards))
                    }
                }
                .font(.system(.title3, design: .monospaced, weight: .semibold))
            }
            Text(hint)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(hintColor)
                .accessibilityIdentifier("battle-hint")
            Capsule()
                .fill(mint.opacity(0.52))
                .frame(width: 52, height: 3)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 70)
        .allowsHitTesting(false)
        .overlay(alignment: .topTrailing) {
            if case .practice = model.mode, model.state == .ready {
                Button(tr("跳过"), action: model.skipPractice)
                    .font(.caption.weight(.semibold))
                    .frame(minWidth: 48, minHeight: 48)
                    .buttonStyle(.glass)
                    .offset(y: -67)
                    .accessibilityIdentifier("skip-practice")
            }
        }
    }

    private var hintColor: Color {
        if model.hud.locks.canCleanse { return yellow }
        if model.hud.locks.hazards > 0 || model.hud.danger { return red }
        return mint
    }

    private var hint: String {
        if model.state == .resumeArmed { return tr("按住继续") }
        if model.hud.recovering { return tr("空斩冷却中") }
        if case .practice(.overload) = model.mode { return tr("持续按住，直到攻击环触及红线") }
        if model.hud.locks.canCleanse { return tr("净斩就绪 · 松手") }
        if model.hud.danger { return tr("即将过载 · 注意红线") }
        if model.hud.locks.hazards > 0 { return tr("红雷在环内 · 凑齐三杀再松手") }
        if case let .practice(lesson) = model.mode {
            if lesson == .capture && model.hud.locks.enemies > 0 { return tr("已锁定晶核 · 松手瞬斩") }
            if lesson == .multiKill || lesson == .mine { return tr("按住扩环 · 锁定三个晶核") }
            return tr("按住，直到攻击环圈住晶核")
        }
        return model.state == .ready ? tr("按住开始") : tr("按住扩环 · 松手瞬斩")
    }

    private var actionOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(model.state == .paused ? 0.28 : 0.22)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.state == .paused {
                        Text(tr("已暂停")).font(.title.bold()).accessibilityAddTraits(.isHeader)
                        PrimaryButton(title: tr("继续"), icon: "play.fill", action: model.armResume)
                            .accessibilityIdentifier("resume-game")
                        SecondaryButton(title: tr("重新开始"), icon: "arrow.counterclockwise", action: model.restartGame)
                        HStack(spacing: 10) {
                            SecondaryButton(title: tr("设置"), icon: "gearshape", action: showSettings)
                            SecondaryButton(title: tr("返回首页"), icon: "house", action: model.showHome)
                        }
                    } else if let result = model.result {
                        ClassicResult(result: result, newBest: model.newBest, restart: model.restartGame, home: model.showHome)
                    } else {
                        Text(model.practiceFailed ? tr("训练重试") : tr("训练完成"))
                            .font(.title.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text(lessonDetail).font(.subheadline).foregroundStyle(.secondary)
                        PrimaryButton(title: lessonAction, icon: "arrow.right", action: model.advanceLesson)
                            .accessibilityIdentifier("advance-lesson")
                        SecondaryButton(title: tr("跳过训练"), icon: "forward.end", action: model.skipPractice)
                    }
                }
                .padding(19)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30))
                .overlay { RoundedRectangle(cornerRadius: 30).strokeBorder(.white.opacity(0.09)) }
                .frame(maxWidth: 510)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var lessonAction: String {
        if model.practiceFailed { return tr("重试") }
        if model.mode == .practice(.overload) { return tr("进入经典模式") }
        return tr("下一步")
    }

    private var lessonDetail: String {
        if model.practiceFailed, let cause = model.core?.death?.cause { return cause.detail }
        switch model.mode {
        case .practice(.capture): return tr("攻击环锁定的晶核，会在松手时被斩碎。")
        case .practice(.multiKill): return tr("一斩击中三个目标，就会触发金色净斩。")
        case .practice(.mine): return tr("净斩能清除环内红雷。")
        default: return tr("扩环触及红线会结束对局。接近红线时及时松手。")
        }
    }
}

private struct ClassicResult: View {
    let result: RunRecord
    let newBest: Bool
    let restart: () -> Void
    let home: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(result.stats.score.formatted())
                    .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                    .accessibilityLabel(String(format: tr("本局得分 %@"), result.stats.score.formatted()))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(newBest ? tr("新纪录") : rank)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(newBest ? yellow : mint)
            }
            Text(result.cause.title).font(.headline).foregroundStyle(red)
            Text(result.cause.detail).font(.subheadline).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { runMetrics }
                VStack(alignment: .leading, spacing: 9) { runMetrics }
            }
            .padding(.vertical, 3)
            PrimaryButton(title: tr("再来一局"), icon: "arrow.counterclockwise", action: restart)
                .accessibilityIdentifier("restart-game")
            SecondaryButton(title: tr("返回首页"), icon: "house", action: home)
        }
    }

    @ViewBuilder private var runMetrics: some View {
        metric(tr("存活"), timeLabel(result.stats.duration))
        metric(tr("最大单斩"), "×\(result.stats.maxSnap)")
        metric(tr("净斩"), result.stats.cleanses.formatted())
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.headline, design: .monospaced))
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.trailing, 12)
        .accessibilityElement(children: .combine)
    }

    private var rank: String {
        let ranks = [(0, "微光环徒"), (200, "青锋捕手"), (550, "白银破阵"), (1100, "流金瞬斩"), (2000, "曜石剑心"), (3500, "极夜无双"), (5500, "星冕主宰")]
        return tr(ranks.last { result.stats.score >= $0.0 }?.1 ?? "微光环徒")
    }
}

private struct PrimaryButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 46)
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.glassProminent)
        .tint(mint)
        .foregroundStyle(night)
        .controlSize(.large)
    }
}

private struct SecondaryButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 45)
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.glass)
        .foregroundStyle(.primary)
    }
}

private struct SettingsView: View {
    @Bindable var model: GameModel
    let startPractice: () -> Void
    let canStartPractice: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section(tr("声音与触觉")) {
                Slider(value: $model.settings.volume, in: 0...1, step: 0.05) {
                    Text(tr("音量"))
                } minimumValueLabel: { Image(systemName: "speaker") }
                  maximumValueLabel: { Image(systemName: "speaker.wave.3") }
                .accessibilityLabel(tr("音量"))
                Toggle(tr("触觉反馈"), isOn: $model.settings.haptics)
            }
            Section(tr("战斗画面")) {
                Toggle(tr("屏幕震动"), isOn: $model.settings.shake)
                Toggle(tr("显示目标轮廓"), isOn: $model.settings.showMarkers)
                VStack(alignment: .leading) {
                    Text(tr("光效强度"))
                    Slider(value: $model.settings.flash, in: 0...1, step: 0.05)
                        .accessibilityLabel(tr("光效强度"))
                }
            }
            if canStartPractice { Button(tr("重新开始训练"), action: startPractice) }
        }
        .navigationTitle(tr("设置"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("完成")) { dismiss() } } }
    }
}

private struct RecordsView: View {
    let records: PlayerRecords
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section(tr("个人纪录")) {
                LabeledContent(tr("最高分"), value: records.bestScore.formatted())
                LabeledContent(tr("最长存活"), value: timeLabel(records.longest))
                LabeledContent(tr("最大单斩"), value: "×\(records.maxSnap)")
                LabeledContent(tr("净斩总数"), value: records.cleanses.formatted())
                LabeledContent(tr("清除红雷"), value: records.minesBroken.formatted())
            }
            Section(tr("瞬斩奖励")) {
                LabeledContent(tr("贴脸"), value: records.bonuses[.closeCut, default: 0].formatted())
                LabeledContent(tr("擦雷"), value: records.bonuses[.mineGraze, default: 0].formatted())
                LabeledContent(tr("破雷"), value: records.bonuses[.mineBreak, default: 0].formatted())
                LabeledContent(tr("满弓"), value: records.bonuses[.fullDraw, default: 0].formatted())
            }
            Section(tr("最近对局")) {
                if records.recent.isEmpty { Text(tr("完成一局后，成绩会出现在这里。")).foregroundStyle(.secondary) }
                ForEach(records.recent) { run in
                    LabeledContent {
                        Text(run.stats.score.formatted()).monospacedDigit()
                    } label: {
                        Text(run.cause.title)
                        Text(run.date.formatted(date: .abbreviated, time: .shortened) + " · " + timeLabel(run.stats.duration))
                    }
                }
            }
        }
        .navigationTitle(tr("纪录"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("完成")) { dismiss() } } }
    }
}
