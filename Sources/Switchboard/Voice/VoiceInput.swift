import AVFoundation
import Observation
import Speech
import os

/// Continuous speech to text: `start` opens the microphone and keeps it open
/// until `finish` (the same shortcut again). Each pause in speech ends one utterance, which
/// is handed to `onTranscript`, and recognition carries straight on with the
/// next. Recognition runs on device when the language allows.
///
/// Every utterance gets its own recognition request, because a request ends
/// for good when the recogniser finalises it (on-device recognition does this
/// after a short silence) and requests are limited to about a minute.
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
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    /// The request the microphone tap currently feeds; swapped per utterance.
    @ObservationIgnored private let feed = RequestFeed()
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var latest = ""
    @ObservationIgnored private var pauseTimer: Task<Void, Never>?
    @ObservationIgnored private var starting = false
    /// Bumped on every session start and stop so stale callbacks are ignored.
    @ObservationIgnored private var session = 0
    /// Bumped on every utterance so a finished request's late callbacks are ignored.
    @ObservationIgnored private var utterance = 0
    /// Recogniser errors in a row with nothing heard; a few in quick
    /// succession mean recognition is broken rather than the room quiet.
    @ObservationIgnored private var emptyFailures: [ContinuousClock.Instant] = []

    /// How long a pause ends an utterance once something has been heard.
    private static let pause: Duration = .milliseconds(1600)

    func toggle() {
        if isListening { finish() } else { Task { await start() } }
    }

    func start() async {
        guard !isListening, !starting else { return }
        starting = true
        defer { starting = false }
        session += 1
        let current = session
        if let problem = await Self.authorize() {
            fail(problem)
            return
        }
        guard current == session else { return }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            fail("Speech recognition isn't available right now.")
            return
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail("No microphone is available.")
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.feeding(feed))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            fail("Couldn't start the microphone: \(error.localizedDescription)")
            return
        }

        self.engine = engine
        self.recognizer = recognizer
        emptyFailures = []
        state = .listening(partial: "")
        beginUtterance()
    }

    /// Stops listening and delivers anything heard since the last pause.
    func finish() {
        guard isListening else { return }
        let transcript = latest
        teardown()
        state = .idle
        if !transcript.isEmpty { onTranscript?(transcript) }
    }

    // MARK: Utterances

    private func beginUtterance() {
        guard let recognizer else { return }
        endRecognition()
        utterance += 1
        let current = utterance

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.contextualStrings = ["Switchboard"]
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        latest = ""
        feed.set(request)
        task = recognizer.recognitionTask(with: request, resultHandler: Self.handler { [weak self] text, isFinal, failed in
            self?.received(text: text, isFinal: isFinal, failed: failed, utterance: current)
        })
    }

    private func received(text: String?, isFinal: Bool, failed: Bool, utterance: Int) {
        guard utterance == self.utterance, isListening else { return }
        if let text, !text.isEmpty {
            latest = text
            emptyFailures = []
            state = .listening(partial: text)
            schedulePause()
        }
        if isFinal {
            completeUtterance()
        } else if failed {
            if latest.isEmpty, tooManyEmptyFailures() {
                fail("Speech recognition stopped working. Press ⌘⇧Space to try again.")
                return
            }
            // Usually "no speech detected" after a quiet spell, or the
            // per-request time limit: keep what was heard and carry on.
            completeUtterance()
        }
    }

    /// Hands over what was heard and starts listening for the next utterance.
    private func completeUtterance() {
        pauseTimer?.cancel()
        pauseTimer = nil
        let transcript = latest
        beginUtterance()
        state = .listening(partial: "")
        if !transcript.isEmpty { onTranscript?(transcript) }
    }

    private func tooManyEmptyFailures() -> Bool {
        let now = ContinuousClock.now
        emptyFailures = emptyFailures.filter { now - $0 < .seconds(10) } + [now]
        return emptyFailures.count >= 3
    }

    // MARK: Timers

    private func schedulePause() {
        pauseTimer?.cancel()
        let current = utterance
        pauseTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.pause)
            guard !Task.isCancelled, let self, self.utterance == current, self.isListening else { return }
            self.completeUtterance()
        }
    }

    // MARK: Teardown

    private func fail(_ message: String) {
        teardown()
        state = .failed(message)
        let current = session
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, self.session == current, case .failed = self.state else { return }
            self.state = .idle
        }
    }

    private func endRecognition() {
        feed.set(nil)
        task?.cancel()
        task = nil
    }

    private func teardown() {
        session += 1
        utterance += 1
        pauseTimer?.cancel()
        pauseTimer = nil
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        recognizer = nil
        endRecognition()
        latest = ""
    }

    // MARK: Off the main actor

    /// The tap runs on the audio thread, so it is built outside the actor.
    private nonisolated static func feeding(_ feed: RequestFeed) -> AVAudioNodeTapBlock {
        { buffer, _ in feed.append(buffer) }
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

/// The recognition request the audio thread appends to, swapped from the
/// main actor at each utterance boundary.
private final class RequestFeed: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<SFSpeechAudioBufferRecognitionRequest?>(initialState: nil)

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.withLock { $0 = request }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { $0 }?.append(buffer)
    }
}
