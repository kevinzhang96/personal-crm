// The microphone screen: a clock, a pulse, and one button. Recording
// starts as soon as permission allows, because the reason the sheet is
// open is that the reader has already decided to talk.

import SwiftUI

struct RecordSheet: View {
    let onFinish: (String, TimeInterval) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = Recorder()
    @State private var denied = false
    @AppStorage("appearance") private var appearance = Appearance.dark.rawValue

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 28) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.18))
                        .frame(width: 180, height: 180)
                        .scaleEffect(1 + CGFloat(recorder.level) * 0.6)
                        .animation(.easeOut(duration: 0.12), value: recorder.level)
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 96, height: 96)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(EntryEditorView.clock(recorder.elapsed))
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                if denied {
                    Text("Microphone access is off. Enable it in Settings → Tend.")
                        .font(.footnote).foregroundStyle(Theme.warn).multilineTextAlignment(.center)
                } else if let error = recorder.error {
                    Text(error).font(.footnote).foregroundStyle(Theme.warn)
                } else {
                    Text(recorder.isRecording ? "Recording · stays on your phone" : "Starting…")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                GlassEffectContainer(spacing: 16) {
                    HStack(spacing: 16) {
                        Button {
                            if let r = recorder.stop() { AudioStore.delete(r.file) }
                            dismiss()
                        } label: {
                            Text("Cancel").font(.subheadline.weight(.semibold)).padding(.horizontal, 22).padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        Button {
                            if let r = recorder.stop() { onFinish(r.file, r.duration) }
                            dismiss()
                        } label: {
                            Label("Done", systemImage: "stop.fill").font(.subheadline.weight(.bold)).padding(.horizontal, 26).padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(Theme.accent).interactive(), in: .capsule)
                        .disabled(!recorder.isRecording)
                    }
                }
                .padding(.bottom, 30)
            }
            .padding()
        }
        .task {
            if await Recorder.requestPermission() { recorder.start() } else { denied = true }
        }
        .interactiveDismissDisabled(recorder.isRecording)
        .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
    }
}
