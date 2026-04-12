import AVFoundation
import Foundation
import Speech

final class SpeechCoordinator: NSObject, ObservableObject, @unchecked Sendable, AVSpeechSynthesizerDelegate {
    @Published var transcript: String = ""
    @Published var canUseSpeechInput = false
    @Published var isListening = false
    @Published var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func warmUp() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            self?.canUseSpeechInput = (status == .authorized)
        }
    }

    func toggleListening(onText: @escaping @Sendable (String) async -> Void) async {
        if isListening {
            stopListening()
        } else {
            do {
                try startListening(onText: onText)
            } catch {
                transcript = error.localizedDescription
            }
        }
    }

    func speak(_ text: String) {
        let speechText = sanitizeForSpeech(text)
        guard !speechText.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = true

        let utterance = AVSpeechUtterance(string: speechText)
        utterance.rate = 0.45
        utterance.pitchMultiplier = 1.15
        utterance.volume = 0.95
        if let voice =
            AVSpeechSynthesisVoice(language: "ru-RU") ??
            AVSpeechSynthesisVoice(language: "uk-UA") ??
            AVSpeechSynthesisVoice(language: "en-US")
        {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }

    private func sanitizeForSpeech(_ text: String) -> String {
        var cleaned = text

        cleaned = cleaned.replacingOccurrences(of: #"[*_`#>"-]"#, with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #":[a-zA-Z0-9_+-]+:"# , with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\p{Emoji_Presentation}|\p{Emoji}\uFE0F"#, with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stopListening() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isListening = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeaking = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }

    private func startListening(onText: @escaping @Sendable (String) async -> Void) throws {
        guard canUseSpeechInput else {
            throw SpeechError.notAuthorized
        }
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechError.unavailable
        }

        stopListening()
        transcript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let formatted = result.bestTranscription.formattedString
                self.transcript = formatted

                if result.isFinal {
                    let finalText = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.stopListening()
                    if !finalText.isEmpty {
                        Task {
                            await onText(finalText)
                        }
                    }
                }
            }

            if error != nil {
                self.stopListening()
            }
        }
    }
}

enum SpeechError: LocalizedError {
    case notAuthorized
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech input permission is not available yet."
        case .unavailable:
            return "Speech recognition is currently unavailable."
        }
    }
}
