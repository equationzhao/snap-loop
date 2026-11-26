import AVFoundation
import UIKit

@MainActor
final class Feedback {
    private let audio = AudioFeedback()
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let warning = UINotificationFeedbackGenerator()
    private var haptics = true

    func prepareSounds() {
        audio.prepareSounds()
    }

    func applySettings(_ settings: PlayerSettings) {
        haptics = settings.haptics
        audio.setVolume(settings.volume)
    }

    func consumeEvent(_ event: GameEvent) {
        switch event {
        case .touch:
            audio.playSound(.touch)
            if haptics { soft.impactOccurred(intensity: 0.45) }
        case .charge:
            audio.playSound(.touch)
            audio.playSound(.charge)
            if haptics { soft.impactOccurred(intensity: 0.6) }
        case let .lock(cleanseReady):
            audio.playSound(cleanseReady ? .cleanse : .lock)
            if cleanseReady && haptics { rigid.impactOccurred(intensity: 0.6) }
        case .warning:
            audio.playSound(.warning)
            if haptics { warning.notificationOccurred(.warning) }
        case let .snap(effect):
            audio.stopCharge()
            audio.playSound(effect.isCleanse ? .cleanse : (effect.award == nil ? .empty : .shot))
            if haptics { rigid.impactOccurred(intensity: effect.isCleanse ? 1 : 0.54) }
        case .defeat:
            audio.stopCharge()
            audio.playSound(.defeat)
            if haptics { warning.notificationOccurred(.error) }
        case .lessonComplete:
            audio.stopCharge()
        case let .beat(accent): audio.playSound(accent ? .accent : .pulse)
        case .stage: audio.playSound(.cleanse)
        case .fuse: audio.playSound(.fuse)
        }
    }

    func stopAll() {
        audio.stopSounds()
    }
}

// The serial queue owns all audio state and keeps playback commands in game event order.
private final class AudioFeedback: @unchecked Sendable {
    enum Cue: CaseIterable, Sendable {
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

    private let queue = DispatchQueue(label: "dev.equationzhao.SnapLoop.audio", qos: .userInitiated)
    private var players: [Cue: AVAudioPlayer] = [:]
    private var volume = 0.65

    func prepareSounds() {
        queue.async { [self] in
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
    }

    func setVolume(_ level: Double) {
        queue.async { [self] in
            volume = level
            for player in players.values {
                player.volume = Float(level)
                if level == 0 && player.isPlaying { player.stop() }
            }
        }
    }

    func playSound(_ cue: Cue) {
        queue.async { [self] in
            guard volume > 0, let player = players[cue] else { return }
            player.currentTime = 0
            player.play()
        }
    }

    func stopCharge() {
        queue.async { [self] in
            if let player = players[.charge], player.isPlaying { player.stop() }
        }
    }

    func stopSounds() {
        queue.async { [self] in
            for player in players.values where player.isPlaying { player.stop() }
        }
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
