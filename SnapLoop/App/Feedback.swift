import AVFoundation
import UIKit

@MainActor
final class Feedback {
    private enum Cue: CaseIterable {
        case charge, touch, lock, cleanse, shot, empty, warning, defeat, pulse, accent, fuse

        var sound: (start: Double, end: Double, duration: Double, gain: Double) {
            switch self {
            case .charge: (110, 110, 0.4, 0.11)
            case .touch: (240, 480, 0.055, 0.19)
            case .lock: (620, 720, 0.06, 0.15)
            case .cleanse: (420, 1160, 0.24, 0.42)
            case .shot: (530, 88, 0.16, 0.42)
            case .empty: (190, 90, 0.10, 0.18)
            case .warning: (260, 190, 0.14, 0.30)
            case .defeat: (280, 35, 0.40, 0.42)
            case .pulse: (72, 48, 0.075, 0.08)
            case .accent: (92, 45, 0.13, 0.12)
            case .fuse: (550, 350, 0.055, 0.09)
            }
        }
    }

    private var players: [Cue: AVAudioPlayer] = [:]
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let warning = UINotificationFeedbackGenerator()
    private var volume = 0.65
    private var haptics = true
    private var prepared = false

    func prepareSounds() {
        guard !prepared else { return }
        prepared = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        for cue in Cue.allCases {
            if let player = try? AVAudioPlayer(data: makeWave(cue)) {
                player.volume = Float(volume)
                player.numberOfLoops = cue == .charge ? -1 : 0
                player.prepareToPlay()
                players[cue] = player
            }
        }
    }

    func applySettings(_ settings: PlayerSettings) {
        volume = settings.volume
        haptics = settings.haptics
        for player in players.values { player.volume = Float(volume) }
        if volume == 0 { stopAll() }
    }

    func consumeEvent(_ event: GameEvent) {
        switch event {
        case .touch:
            playSound(.touch)
            if haptics { soft.impactOccurred(intensity: 0.45) }
        case .charge:
            playSound(.touch)
            playSound(.charge)
            if haptics { soft.impactOccurred(intensity: 0.6) }
        case let .lock(cleanseReady):
            playSound(cleanseReady ? .cleanse : .lock)
            if cleanseReady && haptics { rigid.impactOccurred(intensity: 0.6) }
        case .warning:
            playSound(.warning)
            if haptics { warning.notificationOccurred(.warning) }
        case let .snap(effect):
            players[.charge]?.stop()
            playSound(effect.isCleanse ? .cleanse : (effect.award == nil ? .empty : .shot))
            if haptics { rigid.impactOccurred(intensity: effect.isCleanse ? 1 : 0.54) }
        case .defeat:
            players[.charge]?.stop()
            playSound(.defeat)
            if haptics { warning.notificationOccurred(.error) }
        case .lessonComplete:
            players[.charge]?.stop()
        case let .beat(accent): playSound(accent ? .accent : .pulse)
        case .stage: playSound(.cleanse)
        case .fuse: playSound(.fuse)
        }
    }

    func stopAll() {
        for player in players.values { player.stop() }
    }

    private func playSound(_ cue: Cue) {
        guard volume > 0, let player = players[cue] else { return }
        player.currentTime = 0
        player.play()
    }

    private func makeWave(_ cue: Cue) -> Data {
        let sound = cue.sound
        let rate = 22_050
        let samples = Int(Double(rate) * sound.duration)
        var data = Data()
        func appendValue<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        appendValue(UInt32(36 + samples * 2))
        data.append(contentsOf: "WAVEfmt ".utf8)
        appendValue(UInt32(16))
        appendValue(UInt16(1))
        appendValue(UInt16(1))
        appendValue(UInt32(rate))
        appendValue(UInt32(rate * 2))
        appendValue(UInt16(2))
        appendValue(UInt16(16))
        data.append(contentsOf: "data".utf8)
        appendValue(UInt32(samples * 2))
        var phase = 0.0
        for index in 0..<samples {
            let t = Double(index) / Double(samples)
            let frequency = sound.start * pow(sound.end / sound.start, t)
            phase += 2 * .pi * frequency / Double(rate)
            let envelope = cue == .charge ? 0.7 + 0.3 * sin(2 * .pi * t) : min(1, t * 36) * pow(1 - t, 2)
            let shape = sin(phase) * 0.8 + sin(phase * 2) * 0.15 + sin(phase * 3) * 0.05
            appendValue(Int16(Double(Int16.max) * envelope * shape * sound.gain))
        }
        return data
    }
}
