// Speech to text for one file. On-device whenever the device can, since
// the recording is about a friend; the recogniser's servers are the
// fallback rather than the default.

import Foundation
import Speech

enum Transcriber {
    enum Failure: Error, LocalizedError {
        case denied, unavailable, empty

        var errorDescription: String? {
            switch self {
            case .denied: "Speech recognition isn't allowed. Enable it in Settings → Tend."
            case .unavailable: "Speech recognition isn't available right now."
            case .empty: "Nothing recognisable in the recording."
            }
        }
    }

    static func authorize() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    static func transcribe(_ url: URL, locale: Locale = .current) async throws -> String {
        guard await authorize() else { throw Failure.denied }
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(),
              recognizer.isAvailable
        else { throw Failure.unavailable }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.addsPunctuation = true
        let text: String = try await withCheckedThrowingContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if let error {
                    finished = true
                    continuation.resume(throwing: error)
                }
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.empty }
        return trimmed
    }
}
