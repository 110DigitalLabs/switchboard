import AVFoundation
import Observation
import Speech

/// One utterance of speech to text: `start` listens on the microphone, and the
/// transcript is handed to `onTranscript` after a pause in speech or when
/// `finish` is called. Recognition runs on device when the language allows.
@MainActor
@Observable
final class VoiceInput {
    enum State: Equatable {
        case idle
        case listening(partial: String)
        case failed(String)
    }

    private(set) var state: State = .idle
    @ObservationIgnored var onTranscript: ((String) -> Void)?

    var isListening: Bool {
        if case .listening = state { return true }
        return false
    }

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var latest = ""
    @ObservationIgnored private var finishing = false
    @ObservationIgnored private var timer: Task<Void, Never>?
    /// Bumped on every start and stop so stale callbacks are ignored.
    @ObservationIgnored private var generation = 0

    /// How long a pause ends the utterance once something has been heard.
    private static let pause: Duration = .milliseconds(1600)
    /// How long to wait for the first word before giving up.
    private static let silence: Duration = .seconds(8)
    /// How long `finish` waits for the recogniser's final result.
    private static let finalResultGrace: Duration = .milliseconds(1200)

    func toggle() {
        if isListening { finish() } else { Task { await start() } }
    }

    func start() async {
        guard !isListening else { return }
        generation += 1
        let current = generation
        if let problem = await Self.authorize() {
            fail(problem)
            return
        }
        guard current == generation else { return }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            fail("Speech recognition isn't available right now.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.contextualStrings = ["Switchboard"]
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail("No microphone is available.")
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.feeding(request))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            fail("Couldn't start the microphone: \(error.localizedDescription)")
            return
        }

        self.engine = engine
        self.request = request
        latest = ""
        finishing = false
        state = .listening(partial: "")
        task = recognizer.recognitionTask(with: request, resultHandler: Self.handler { [weak self] text, isFinal, failed in
            self?.received(text: text, isFinal: isFinal, failed: failed, generation: current)
        })
        schedule(after: Self.silence) { $0.cancel() }
    }

    /// Stops listening and delivers what was heard.
    func finish() {
        guard isListening, !finishing else { return }
        finishing = true
        stopAudio()
        request?.endAudio()
        // The recogniser usually sends its final result within a moment;
        // fall back to the last partial if it doesn't.
        schedule(after: Self.finalResultGrace) { $0.deliver() }
    }

    /// Stops listening and drops what was heard.
    func cancel() {
        guard isListening || finishing else { return }
        teardown()
        state = .idle
    }

    private func received(text: String?, isFinal: Bool, failed: Bool, generation: Int) {
        guard generation == self.generation, isListening else { return }
        if let text, !text.isEmpty {
            latest = text
            state = .listening(partial: text)
            if !finishing { schedule(after: Self.pause) { $0.finish() } }
        }
        if isFinal || (failed && finishing) {
            deliver()
        } else if failed, latest.isEmpty {
            // Errors with nothing heard are usually "no speech detected".
            cancel()
        } else if failed {
            deliver()
        }
    }

    private func deliver() {
        let transcript = latest
        teardown()
        state = .idle
        if !transcript.isEmpty { onTranscript?(transcript) }
    }

    private func fail(_ message: String) {
        teardown()
        state = .failed(message)
        let current = generation
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, self.generation == current, case .failed = self.state else { return }
            self.state = .idle
        }
    }

    private func schedule(after delay: Duration, _ action: @escaping @MainActor (VoiceInput) -> Void) {
        timer?.cancel()
        let current = generation
        timer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.generation == current else { return }
            action(self)
        }
    }

    private func stopAudio() {
        guard let engine else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        self.engine = nil
    }

    private func teardown() {
        generation += 1
        timer?.cancel()
        timer = nil
        stopAudio()
        task?.cancel()
        task = nil
        request = nil
        latest = ""
        finishing = false
    }

    // MARK: Off the main actor

    /// The tap runs on the audio thread, so it is built outside the actor.
    private nonisolated static func feeding(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    private nonisolated static func handler(
        _ deliver: @escaping @MainActor (String?, Bool, Bool) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in deliver(text, isFinal, failed) }
        }
    }

    /// Asks for speech recognition and microphone access; nil when both are granted.
    private nonisolated static func authorize() async -> String? {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            return "Allow Switchboard under System Settings › Privacy & Security › Speech Recognition."
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            return "Allow Switchboard under System Settings › Privacy & Security › Microphone."
        }
        return nil
    }
}
