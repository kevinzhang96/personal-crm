// The microphone, as a screen sees it: a level, a clock, and a file when
// it stops. Recording under half a second is a mis-tap and is discarded.

import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class Recorder {
    private(set) var isRecording = false
    /// 0…1, from the meter — the pulse the record screen shows.
    private(set) var level: Float = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var error: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileName: String?

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() {
        guard !isRecording else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let name = AudioStore.newFileName()
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: AudioStore.url(for: name), settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                error = "Couldn't start recording."
                return
            }
            self.recorder = recorder
            fileName = name
            isRecording = true
            elapsed = 0
            error = nil
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func tick() {
        guard let recorder else { return }
        recorder.updateMeters()
        // averagePower is dBFS, silence around -50; map to a 0…1 pulse.
        level = max(0, min(1, (recorder.averagePower(forChannel: 0) + 50) / 50))
        elapsed = recorder.currentTime
    }

    /// Stops and hands back the file, or nothing when there is nothing
    /// worth keeping.
    func stop() -> (file: String, duration: TimeInterval)? {
        timer?.invalidate()
        timer = nil
        guard let recorder, let fileName else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.fileName = nil
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard duration >= 0.5 else {
            AudioStore.delete(fileName)
            return nil
        }
        return (fileName, duration)
    }
}

/// Playback of one recording at a time.
@MainActor
@Observable
final class Player: NSObject, AVAudioPlayerDelegate {
    private(set) var isPlaying = false
    private(set) var playingFile: String?
    private var player: AVAudioPlayer?

    func toggle(_ file: String) {
        if isPlaying, playingFile == file {
            stop()
            return
        }
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: AudioStore.url(for: file))
            player.delegate = self
            player.play()
            self.player = player
            playingFile = file
            isPlaying = true
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        playingFile = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
