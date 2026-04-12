import AVFoundation
import Foundation
import Speech

final class SpeechCoordinator: NSObject, ObservableObject, @unchecked Sendable, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published var transcript: String = ""
    @Published var canUseSpeechInput = false
    @Published var isListening = false
    @Published var isSpeaking = false
    @Published var lastStatusMessage = ""

    private let synthesizer = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioPlayer: AVAudioPlayer?
    private var currentAudioFileURL: URL?
    private var currentPiperProcess: Process?

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
                updateStatus(error.localizedDescription)
                transcript = error.localizedDescription
            }
        }
    }

    func speak(_ text: String, profile: CompanionProfile) {
        let speechText = sanitizeForSpeech(text)
        guard !speechText.isEmpty else { return }

        stopCurrentPlayback()
        updateStatus("")

        switch profile.ttsProvider {
        case .system:
            speakWithSystemVoice(speechText, language: profile.responseLanguage)
        case .piper:
            speakWithPiper(speechText, executablePath: profile.piperExecutablePath, modelPath: profile.piperModelPath)
        }
    }

    func previewVoice(profile: CompanionProfile) {
        let sample: String
        switch profile.responseLanguage {
        case .russian:
            sample = "Привет. Я рядом, и мой голос уже работает."
        case .ukrainian:
            sample = "Привіт. Я поруч, і мій голос уже працює."
        case .english:
            sample = "Hi. I am right here, and my voice is working."
        }

        speak(sample, profile: profile)
    }

    private func speakWithSystemVoice(_ text: String, language: CompanionResponseLanguage) {
        setSpeaking(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.45
        utterance.pitchMultiplier = 1.15
        utterance.volume = 0.95

        let preferredLanguages = systemVoiceLanguageCandidates(for: language)
        for code in preferredLanguages {
            if let voice = AVSpeechSynthesisVoice(language: code) {
                utterance.voice = voice
                break
            }
        }

        synthesizer.speak(utterance)
    }

    private func speakWithPiper(_ text: String, executablePath: String, modelPath: String) {
        let resolvedExecutable = resolvePiperExecutablePath(from: executablePath)
        let resolvedModel = resolvePiperModelPath(from: modelPath)
        let trimmedExecutable = resolvedExecutable.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = resolvedModel.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedExecutable.isEmpty else {
            updateStatus("Для Piper нужно указать путь к бинарнику.")
            return
        }

        guard !trimmedModel.isEmpty else {
            updateStatus("Для Piper нужно указать путь к voice model (.onnx).")
            return
        }

        let modelURL = URL(fileURLWithPath: NSString(string: trimmedModel).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            updateStatus("Не нашла Piper voice model по пути: \(modelURL.path)")
            return
        }

        let configURL = URL(fileURLWithPath: modelURL.path + ".json")

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("char-piper-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        if trimmedExecutable.contains("/") {
            process.executableURL = URL(fileURLWithPath: NSString(string: trimmedExecutable).expandingTildeInPath)
            var arguments = [
                "--model", modelURL.path,
                "--output_file", outputURL.path,
            ]
            if FileManager.default.fileExists(atPath: configURL.path) {
                arguments.insert(contentsOf: ["--config", configURL.path], at: 2)
            }
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            var arguments = [
                trimmedExecutable,
                "--model", modelURL.path,
                "--output_file", outputURL.path,
            ]
            if FileManager.default.fileExists(atPath: configURL.path) {
                arguments.insert(contentsOf: ["--config", configURL.path], at: 3)
            }
            process.arguments = arguments
        }

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        currentPiperProcess = process
        setSpeaking(true)
        updateStatus("Piper запускается...")

        process.terminationHandler = { [weak self] process in
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            DispatchQueue.main.async {
                self?.currentPiperProcess = nil

                if process.terminationStatus != 0 {
                    self?.setSpeaking(false)
                    self?.cleanupAudioFile()
                    self?.updateStatus(errorText.isEmpty ? "Piper завершился с ошибкой." : errorText)
                    return
                }

                self?.updateStatus("Piper сгенерировал речь.")
                self?.playGeneratedAudio(from: outputURL)
            }
        }

        do {
            try process.run()
            stdinPipe.fileHandleForWriting.write(Data(text.utf8))
            try stdinPipe.fileHandleForWriting.close()
        } catch {
            setSpeaking(false)
            currentPiperProcess = nil
            updateStatus("Не удалось запустить Piper: \(error.localizedDescription)")
        }
    }

    private func resolvePiperExecutablePath(from configuredPath: String) -> String {
        PiperSupport.resolveExecutablePath(configuredPath) ?? configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvePiperModelPath(from configuredPath: String) -> String {
        PiperSupport.resolveModelPath(configuredPath) ?? configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func playGeneratedAudio(from url: URL) {
        cleanupAudioFile()

        do {
            currentAudioFileURL = url
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            audioPlayer = player
            if !player.play() {
                setSpeaking(false)
                updateStatus("Piper сгенерировал файл, но проиграть его не получилось.")
                cleanupAudioFile()
            } else {
                updateStatus("")
            }
        } catch {
            setSpeaking(false)
            updateStatus("Не удалось воспроизвести Piper audio: \(error.localizedDescription)")
            cleanupAudioFile()
        }
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
        setSpeaking(true)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        setSpeaking(false)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        setSpeaking(false)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        setSpeaking(false)
        cleanupAudioFile()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        setSpeaking(false)
        updateStatus(error?.localizedDescription ?? "Ошибка декодирования Piper audio.")
        cleanupAudioFile()
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

    private func stopCurrentPlayback() {
        synthesizer.stopSpeaking(at: .immediate)
        currentPiperProcess?.terminate()
        currentPiperProcess = nil
        audioPlayer?.stop()
        audioPlayer = nil
        cleanupAudioFile()
        setSpeaking(false)
    }

    private func cleanupAudioFile() {
        if let url = currentAudioFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentAudioFileURL = nil
    }

    private func updateStatus(_ message: String) {
        DispatchQueue.main.async {
            self.lastStatusMessage = message
        }
    }

    private func setSpeaking(_ value: Bool) {
        DispatchQueue.main.async {
            self.isSpeaking = value
        }
    }

    private func systemVoiceLanguageCandidates(for language: CompanionResponseLanguage) -> [String] {
        switch language {
        case .russian:
            return ["ru-RU", "uk-UA", "en-US"]
        case .ukrainian:
            return ["uk-UA", "ru-RU", "en-US"]
        case .english:
            return ["en-US", "en-GB", "ru-RU"]
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
