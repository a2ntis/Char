import AVFoundation
import Foundation
import Speech

final class SpeechCoordinator: NSObject, ObservableObject, @unchecked Sendable, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published var transcript: String = ""
    @Published var canUseSpeechInput = false
    @Published var isListening = false
    @Published var isSpeaking = false
    @Published var speechLevel: CGFloat = 0
    @Published var lastStatusMessage = ""

    private let synthesizer = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let streamPlaybackEngine = AVAudioEngine()
    private let streamPlaybackNode = AVAudioPlayerNode()
    private let geminiStreamFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioPlayer: AVAudioPlayer?
    private var currentAudioFileURL: URL?
    private var currentSpeechProcess: Process?
    private var openAITTSSessionID: UUID?
    private var openAIPendingChunkFiles: [Int: URL] = [:]
    private var openAIFailedChunkIndexes: Set<Int> = []
    private var openAINextChunkIndexToPlay = 0
    private var openAITotalChunkCount = 0
    private var openAICompletedChunkCount = 0
    private var openAIHadChunkFailure = false
    private var openAIStreamTask: Task<Void, Never>?
    private var openAIPendingBufferCount = 0
    private var openAIDidFinishStreaming = false
    private var openAIDidStartPlayback = false
    private var geminiStreamTask: Task<Void, Never>?
    private var geminiPendingBufferCount = 0
    private var geminiDidFinishStreaming = false
    private var geminiDidStartPlayback = false
    private var audioMeterTimer: Timer?
    private var speechLevelDecayTimer: Timer?
    private var geminiSpeechLevelHoldUntil: Date?

    override init() {
        super.init()
        synthesizer.delegate = self
        streamPlaybackEngine.attach(streamPlaybackNode)
        if let geminiStreamFormat {
            streamPlaybackEngine.connect(streamPlaybackNode, to: streamPlaybackEngine.mainMixerNode, format: geminiStreamFormat)
        }
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

    func speak(_ text: String, profile: CompanionProfile, openAIAPIKey: String = "") {
        let speechText = sanitizeForSpeech(text)
        guard !speechText.isEmpty else { return }

        stopCurrentPlayback()
        updateStatus("")

        switch profile.ttsProvider {
        case .system:
            speakWithSystemVoice(speechText, language: profile.responseLanguage)
        case .piper:
            speakWithPiper(speechText, executablePath: profile.piperExecutablePath, modelPath: profile.piperModelPath)
        case .xtts:
            speakWithXTTS(speechText, pythonPath: profile.xttsPythonPath, referencePath: profile.xttsReferencePath, language: profile.responseLanguage)
        case .openAI:
            speakWithOpenAI(speechText, profile: profile, apiKey: openAIAPIKey)
        case .gemini:
            speakWithGemini(speechText, profile: profile)
        }
    }

    func previewVoice(profile: CompanionProfile, openAIAPIKey: String = "") {
        let sample: String
        switch profile.responseLanguage {
        case .russian:
            sample = "Привет. Я рядом, и мой голос уже работает."
        case .ukrainian:
            sample = "Привіт. Я поруч, і мій голос уже працює."
        case .english:
            sample = "Hi. I am right here, and my voice is working."
        }

        speak(sample, profile: profile, openAIAPIKey: openAIAPIKey)
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
        currentSpeechProcess = process
        setSpeaking(true)
        updateStatus("Piper запускается...")

        process.terminationHandler = { [weak self] process in
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            DispatchQueue.main.async {
                self?.currentSpeechProcess = nil

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
            currentSpeechProcess = nil
            updateStatus("Не удалось запустить Piper: \(error.localizedDescription)")
        }
    }

    private func speakWithXTTS(_ text: String, pythonPath: String, referencePath: String, language: CompanionResponseLanguage) {
        let resolvedPython = XTTSSupport.resolvePythonPath(pythonPath)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedReference = XTTSSupport.resolveReferencePath(referencePath)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !resolvedPython.isEmpty else {
            updateStatus("Не найден локальный XTTS python runtime.")
            return
        }

        guard !resolvedReference.isEmpty else {
            updateStatus("Для XTTS нужен reference voice clip.")
            return
        }

        let referenceURL = URL(fileURLWithPath: NSString(string: resolvedReference).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: referenceURL.path) else {
            updateStatus("Не найден reference clip для XTTS: \(referenceURL.path)")
            return
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("char-xtts-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: resolvedPython)
        process.environment = {
            var env = ProcessInfo.processInfo.environment
            env["COQUI_TOS_AGREED"] = "1"
            return env
        }()
        process.arguments = [
            "-u",
            "-c",
            xttsPythonScript(outputPath: outputURL.path, referencePath: referenceURL.path, text: text, languageCode: xttsLanguageCode(for: language))
        ]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        currentSpeechProcess = process
        setSpeaking(true)
        updateStatus("XTTS синтезирует речь...")

        process.terminationHandler = { [weak self] process in
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdoutText = String(data: stdoutData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stderrText = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            DispatchQueue.main.async {
                self?.currentSpeechProcess = nil

                guard process.terminationStatus == 0 else {
                    self?.setSpeaking(false)
                    self?.cleanupAudioFile()
                    let message = [stderrText, stdoutText].first(where: { !$0.isEmpty }) ?? "XTTS завершился с ошибкой."
                    self?.updateStatus(message)
                    return
                }

                self?.updateStatus("XTTS сгенерировал речь.")
                self?.playGeneratedAudio(from: outputURL)
            }
        }

        do {
            try process.run()
        } catch {
            setSpeaking(false)
            currentSpeechProcess = nil
            updateStatus("Не удалось запустить XTTS: \(error.localizedDescription)")
        }
    }

    private func speakWithOpenAI(_ text: String, profile: CompanionProfile, apiKey: String) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            updateStatus("Для OpenAI TTS нужен API key.")
            return
        }
        let chunks = speechChunks(for: text)
        guard !chunks.isEmpty else {
            updateStatus("OpenAI TTS не получил текста для озвучки.")
            return
        }

        let model = profile.openAITTSModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "gpt-4o-mini-tts"
            : profile.openAITTSModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let voice = profile.openAITTSVoice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "coral"
            : profile.openAITTSVoice.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = profile.openAITTSInstructions.trimmingCharacters(in: .whitespacesAndNewlines)

        if model == "gpt-4o-mini-tts" {
            speakWithOpenAIStreaming(
                text,
                model: model,
                voice: voice,
                speed: min(max(profile.openAITTSSpeed, 0.25), 4.0),
                instructions: instructions.isEmpty ? nil : instructions,
                endpoint: profile.openAITTSEndpoint,
                apiKey: trimmedKey
            )
            return
        }

        struct RequestBody: Encodable {
            let model: String
            let voice: String
            let input: String
            let format: String
            let speed: Double
            let instructions: String?

            enum CodingKeys: String, CodingKey {
                case model
                case voice
                case input
                case format = "response_format"
                case speed
                case instructions
            }
        }

        var request = URLRequest(url: profile.openAITTSEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(
                RequestBody(
                    model: model,
                    voice: voice,
                    input: text,
                    format: "wav",
                    speed: min(max(profile.openAITTSSpeed, 0.25), 4.0),
                    instructions: instructions.isEmpty ? nil : instructions
                )
            )
        } catch {
            updateStatus("Не удалось подготовить OpenAI TTS запрос: \(error.localizedDescription)")
            return
        }

        let sessionID = UUID()
        openAITTSSessionID = sessionID
        openAIPendingChunkFiles = [:]
        openAIFailedChunkIndexes = []
        openAINextChunkIndexToPlay = 0
        openAITotalChunkCount = chunks.count
        openAICompletedChunkCount = 0
        openAIHadChunkFailure = false
        setSpeaking(true)
        updateStatus("OpenAI TTS готовит первую фразу...")

        for (index, chunk) in chunks.enumerated() {
            requestOpenAIChunk(
                chunk,
                chunkIndex: index,
                sessionID: sessionID,
                model: model,
                voice: voice,
                speed: min(max(profile.openAITTSSpeed, 0.25), 4.0),
                instructions: instructions.isEmpty ? nil : instructions,
                endpoint: profile.openAITTSEndpoint,
                apiKey: trimmedKey
            )
        }
    }

    private func speakWithOpenAIStreaming(
        _ text: String,
        model: String,
        voice: String,
        speed: Double,
        instructions: String?,
        endpoint: URL,
        apiKey: String
    ) {
        struct RequestBody: Encodable {
            let model: String
            let voice: String
            let input: String
            let format: String
            let streamFormat: String
            let speed: Double
            let instructions: String?

            enum CodingKeys: String, CodingKey {
                case model
                case voice
                case input
                case format = "response_format"
                case streamFormat = "stream_format"
                case speed
                case instructions
            }
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        do {
            request.httpBody = try JSONEncoder().encode(
                RequestBody(
                    model: model,
                    voice: voice,
                    input: text,
                    format: "pcm",
                    streamFormat: "sse",
                    speed: speed,
                    instructions: instructions
                )
            )
        } catch {
            updateStatus("Не удалось подготовить OpenAI TTS запрос: \(error.localizedDescription)")
            return
        }

        setSpeaking(true)
        updateStatus("OpenAI TTS готовит поток речи...")
        openAIStreamTask?.cancel()
        openAIPendingBufferCount = 0
        openAIDidFinishStreaming = false
        openAIDidStartPlayback = false
        geminiSpeechLevelHoldUntil = nil
        streamPlaybackNode.stop()

        openAIStreamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OpenAITTSError.invalidResponse
                }
                guard (200..<300).contains(httpResponse.statusCode) else {
                    throw OpenAITTSError.serverMessage("OpenAI TTS вернул ошибку HTTP \(httpResponse.statusCode).")
                }

                for try await line in bytes.lines {
                    if Task.isCancelled { return }
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.hasPrefix("data:") else { continue }
                    let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !payload.isEmpty, payload != "[DONE]" else { continue }
                    guard let jsonData = payload.data(using: .utf8) else { continue }

                    if let event = try? JSONDecoder().decode(OpenAITTSStreamEvent.self, from: jsonData) {
                        switch event.type {
                        case "speech.audio.delta":
                            if let audio = event.audio, let pcmData = Data(base64Encoded: audio) {
                                DispatchQueue.main.async {
                                    self.enqueueOpenAIPCMData(pcmData)
                                }
                            }
                        case "speech.audio.done":
                            DispatchQueue.main.async {
                                self.openAIDidFinishStreaming = true
                                self.finishOpenAIStreamIfNeeded()
                            }
                        default:
                            break
                        }
                    }
                }

                DispatchQueue.main.async {
                    self.openAIDidFinishStreaming = true
                    self.finishOpenAIStreamIfNeeded()
                }
            } catch {
                DispatchQueue.main.async {
                    self.setSpeaking(false)
                    self.updateStatus(error.localizedDescription)
                    self.stopOpenAIStreamPlayback()
                }
            }
        }
    }

    private func speakWithGemini(_ text: String, profile: CompanionProfile) {
        let apiKey = UserDefaults.standard.string(forKey: "googleTTSAPIKey")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !apiKey.isEmpty else {
            updateStatus("Для Gemini TTS нужен Gemini API key.")
            return
        }

        let voiceName = profile.googleTTSVoiceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !voiceName.isEmpty else {
            updateStatus("Для Gemini TTS нужно выбрать голос.")
            return
        }

        let model = profile.googleTTSModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "gemini-2.5-flash-preview-tts"
            : profile.googleTTSModel.trimmingCharacters(in: .whitespacesAndNewlines)

        struct RequestBody: Encodable {
            struct Content: Encodable {
                struct Part: Encodable {
                    let text: String
                }
                let parts: [Part]
            }

            struct GenerationConfig: Encodable {
                struct SpeechConfig: Encodable {
                    struct VoiceConfig: Encodable {
                        struct PrebuiltVoiceConfig: Encodable {
                            let voiceName: String
                        }
                        let prebuiltVoiceConfig: PrebuiltVoiceConfig
                    }

                    let voiceConfig: VoiceConfig
                }

                let responseModalities: [String]
                let speechConfig: SpeechConfig
            }

            let contents: [Content]
            let generationConfig: GenerationConfig
        }

        let effectiveInstructions = profile.googleTTSStyleInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = effectiveInstructions.isEmpty ? text : "\(effectiveInstructions)\n\nSay exactly this text:\n\(text)"

        guard let baseURL = URL(string: "\(profile.googleTTSEndpoint.absoluteString)/models/\(model):streamGenerateContent?alt=sse") else {
            updateStatus("Некорректный endpoint Gemini TTS.")
            return
        }

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        do {
            request.httpBody = try JSONEncoder().encode(
                RequestBody(
                    contents: [
                        .init(parts: [.init(text: prompt)])
                    ],
                    generationConfig: .init(
                        responseModalities: ["AUDIO"],
                        speechConfig: .init(
                            voiceConfig: .init(
                                prebuiltVoiceConfig: .init(voiceName: voiceName)
                            )
                        )
                    )
                )
            )
        } catch {
            updateStatus("Не удалось подготовить Gemini TTS запрос: \(error.localizedDescription)")
            return
        }

        setSpeaking(true)
        updateStatus("Gemini TTS готовит поток речи...")
        geminiStreamTask?.cancel()
        geminiPendingBufferCount = 0
        geminiDidFinishStreaming = false
        geminiDidStartPlayback = false
        streamPlaybackNode.stop()

        geminiStreamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OpenAITTSError.invalidResponse
                }
                guard (200..<300).contains(httpResponse.statusCode) else {
                    throw OpenAITTSError.serverMessage("Gemini TTS вернул ошибку HTTP \(httpResponse.statusCode).")
                }

                for try await line in bytes.lines {
                    if Task.isCancelled { return }
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.hasPrefix("data:") else { continue }
                    let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !payload.isEmpty else { continue }
                    guard let jsonData = payload.data(using: .utf8) else { continue }

                    if let chunk = try? JSONDecoder().decode(GeminiTTSStreamResponse.self, from: jsonData),
                       let base64 = chunk.candidates.first?.content.parts.first(where: { $0.inlineData != nil })?.inlineData?.data,
                       let pcmData = Data(base64Encoded: base64) {
                        DispatchQueue.main.async {
                            self.enqueueGeminiPCMData(pcmData)
                        }
                    }
                }

                DispatchQueue.main.async {
                    self.geminiDidFinishStreaming = true
                    self.finishGeminiStreamIfNeeded()
                }
            } catch {
                DispatchQueue.main.async {
                    self.setSpeaking(false)
                    self.updateStatus(error.localizedDescription)
                    self.stopGeminiStreamPlayback()
                }
            }
        }
    }

    private func enqueueGeminiPCMData(_ pcmData: Data) {
        guard let format = geminiStreamFormat else { return }
        guard let pcmBuffer = makePCMBuffer(from: pcmData, format: format) else { return }
        updateGeminiSpeechLevel(from: pcmData)

        do {
            if !streamPlaybackEngine.isRunning {
                try streamPlaybackEngine.start()
            }
        } catch {
            setSpeaking(false)
            updateStatus("Не удалось запустить аудио-движок Gemini TTS: \(error.localizedDescription)")
            return
        }

        geminiPendingBufferCount += 1
        streamPlaybackNode.scheduleBuffer(pcmBuffer) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.geminiPendingBufferCount = max(0, self.geminiPendingBufferCount - 1)
                self.finishGeminiStreamIfNeeded()
            }
        }

        if !geminiDidStartPlayback {
            geminiDidStartPlayback = true
            streamPlaybackNode.play()
            updateStatus("Gemini TTS начал воспроизведение.")
        }
    }

    private func enqueueOpenAIPCMData(_ pcmData: Data) {
        guard let format = geminiStreamFormat else { return }
        guard let pcmBuffer = makePCMBuffer(from: pcmData, format: format) else { return }
        updateGeminiSpeechLevel(from: pcmData)

        do {
            if !streamPlaybackEngine.isRunning {
                try streamPlaybackEngine.start()
            }
        } catch {
            setSpeaking(false)
            updateStatus("Не удалось запустить аудио-движок OpenAI TTS: \(error.localizedDescription)")
            return
        }

        openAIPendingBufferCount += 1
        streamPlaybackNode.scheduleBuffer(pcmBuffer) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.openAIPendingBufferCount = max(0, self.openAIPendingBufferCount - 1)
                self.finishOpenAIStreamIfNeeded()
            }
        }

        if !openAIDidStartPlayback {
            openAIDidStartPlayback = true
            streamPlaybackNode.play()
            updateStatus("OpenAI TTS начал воспроизведение.")
        }
    }

    private func updateGeminiSpeechLevel(from pcmData: Data) {
        let sampleCount = pcmData.count / MemoryLayout<Int16>.stride
        guard sampleCount > 0 else { return }

        let rms: CGFloat = pcmData.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return 0 }
            var sum: Double = 0
            for index in 0..<sampleCount {
                let sample = Double(base[index]) / Double(Int16.max)
                sum += sample * sample
            }
            return CGFloat(sqrt(sum / Double(sampleCount)))
        }

        setSpeechLevel(min(max(rms * 2.8, 0), 1))
        geminiSpeechLevelHoldUntil = Date().addingTimeInterval(0.08)
        startSpeechLevelDecayIfNeeded()
    }

    private func makePCMBuffer(from pcmData: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return nil }
        let frameCount = UInt32(pcmData.count / bytesPerFrame)
        guard frameCount > 0 else { return nil }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        pcmData.withUnsafeBytes { rawBuffer in
            if let source = rawBuffer.bindMemory(to: Int16.self).baseAddress,
               let destination = buffer.int16ChannelData?.pointee {
                destination.update(from: source, count: Int(frameCount))
            }
        }

        return buffer
    }

    private func finishGeminiStreamIfNeeded() {
        guard geminiDidFinishStreaming, geminiPendingBufferCount == 0 else { return }
        stopGeminiStreamPlayback()
        setSpeaking(false)
        updateStatus("")
    }

    private func stopGeminiStreamPlayback() {
        geminiStreamTask?.cancel()
        geminiStreamTask = nil
        geminiPendingBufferCount = 0
        geminiDidFinishStreaming = false
        geminiDidStartPlayback = false
        geminiSpeechLevelHoldUntil = nil
        streamPlaybackNode.stop()
        streamPlaybackEngine.pause()
        stopSpeechLevelDecay()
        setSpeechLevel(0)
    }

    private func finishOpenAIStreamIfNeeded() {
        guard openAIDidFinishStreaming, openAIPendingBufferCount == 0 else { return }
        stopOpenAIStreamPlayback()
        setSpeaking(false)
        updateStatus("")
    }

    private func stopOpenAIStreamPlayback() {
        openAIStreamTask?.cancel()
        openAIStreamTask = nil
        openAIPendingBufferCount = 0
        openAIDidFinishStreaming = false
        openAIDidStartPlayback = false
        geminiSpeechLevelHoldUntil = nil
        streamPlaybackNode.stop()
        streamPlaybackEngine.pause()
        stopSpeechLevelDecay()
        setSpeechLevel(0)
    }

    private func requestOpenAIChunk(
        _ chunk: String,
        chunkIndex: Int,
        sessionID: UUID,
        model: String,
        voice: String,
        speed: Double,
        instructions: String?,
        endpoint: URL,
        apiKey: String
    ) {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("char-openai-tts-\(sessionID.uuidString)-\(chunkIndex)")
            .appendingPathExtension("wav")

        struct RequestBody: Encodable {
            let model: String
            let voice: String
            let input: String
            let format: String
            let speed: Double
            let instructions: String?

            enum CodingKeys: String, CodingKey {
                case model
                case voice
                case input
                case format = "response_format"
                case speed
                case instructions
            }
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(
                RequestBody(
                    model: model,
                    voice: voice,
                    input: chunk,
                    format: "wav",
                    speed: speed,
                    instructions: instructions
                )
            )
        } catch {
            handleOpenAIChunkFailure(chunkIndex: chunkIndex, sessionID: sessionID, message: "Не удалось подготовить OpenAI TTS запрос: \(error.localizedDescription)")
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                self.handleOpenAIChunkFailure(chunkIndex: chunkIndex, sessionID: sessionID, message: error.localizedDescription)
                return
            }

            guard let data, let httpResponse = response as? HTTPURLResponse else {
                self.handleOpenAIChunkFailure(chunkIndex: chunkIndex, sessionID: sessionID, message: OpenAITTSError.invalidResponse.localizedDescription)
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                self.handleOpenAIChunkFailure(chunkIndex: chunkIndex, sessionID: sessionID, message: Self.extractOpenAIError(from: data))
                return
            }

            do {
                try data.write(to: outputURL)
                DispatchQueue.main.async {
                    guard self.openAITTSSessionID == sessionID else {
                        try? FileManager.default.removeItem(at: outputURL)
                        return
                    }
                    self.openAIPendingChunkFiles[chunkIndex] = outputURL
                    self.openAICompletedChunkCount += 1
                    if chunkIndex == 0 {
                        self.updateStatus("OpenAI TTS сгенерировал первую фразу.")
                    }
                    self.playNextOpenAIChunkIfReady()
                }
            } catch {
                self.handleOpenAIChunkFailure(chunkIndex: chunkIndex, sessionID: sessionID, message: error.localizedDescription)
            }
        }.resume()
    }

    private func handleOpenAIChunkFailure(chunkIndex: Int, sessionID: UUID, message: String) {
        DispatchQueue.main.async {
            guard self.openAITTSSessionID == sessionID else { return }
            self.openAIFailedChunkIndexes.insert(chunkIndex)
            self.openAICompletedChunkCount += 1
            self.openAIHadChunkFailure = true
            if chunkIndex == 0 {
                self.updateStatus(message)
            }
            self.playNextOpenAIChunkIfReady()
        }
    }

    private func playNextOpenAIChunkIfReady() {
        if let audioPlayer, audioPlayer.isPlaying {
            return
        }

        while openAIFailedChunkIndexes.contains(openAINextChunkIndexToPlay) {
            openAINextChunkIndexToPlay += 1
        }

        if let nextURL = openAIPendingChunkFiles.removeValue(forKey: openAINextChunkIndexToPlay) {
            openAINextChunkIndexToPlay += 1
            playGeneratedAudio(from: nextURL)
            return
        }

        if openAICompletedChunkCount >= openAITotalChunkCount,
           openAINextChunkIndexToPlay >= openAITotalChunkCount {
            let hadFailure = openAIHadChunkFailure
            resetOpenAIChunkState()
            setSpeaking(false)
            if hadFailure {
                updateStatus("Часть реплики не удалось озвучить, но остальное проигралось.")
            } else {
                updateStatus("")
            }
        }
    }

    private func resetOpenAIChunkState() {
        for url in openAIPendingChunkFiles.values {
            try? FileManager.default.removeItem(at: url)
        }
        openAITTSSessionID = nil
        openAIPendingChunkFiles = [:]
        openAIFailedChunkIndexes = []
        openAINextChunkIndexToPlay = 0
        openAITotalChunkCount = 0
        openAICompletedChunkCount = 0
        openAIHadChunkFailure = false
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
            player.isMeteringEnabled = true
            player.prepareToPlay()
            audioPlayer = player
            if !player.play() {
                setSpeaking(false)
                updateStatus("Piper сгенерировал файл, но проиграть его не получилось.")
                cleanupAudioFile()
            } else {
                startAudioMetering()
                updateStatus("")
            }
        } catch {
            setSpeaking(false)
            updateStatus("Не удалось воспроизвести Piper audio: \(error.localizedDescription)")
            cleanupAudioFile()
        }
    }

    private func startAudioMetering() {
        stopAudioMetering()
        audioMeterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard let player = self.audioPlayer, player.isPlaying else {
                self.setSpeechLevel(0)
                return
            }

            player.updateMeters()
            let averagePower = player.averagePower(forChannel: 0)
            let clamped = max(-60.0, min(0.0, averagePower))
            let normalized = pow(10.0, clamped / 20.0)
            self.setSpeechLevel(CGFloat(normalized))
        }

        if let audioMeterTimer {
            RunLoop.main.add(audioMeterTimer, forMode: .common)
        }
    }

    private func stopAudioMetering() {
        audioMeterTimer?.invalidate()
        audioMeterTimer = nil
        setSpeechLevel(0)
    }

    private func startSpeechLevelDecayIfNeeded() {
        guard speechLevelDecayTimer == nil else { return }
        speechLevelDecayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            if let holdUntil = self.geminiSpeechLevelHoldUntil, now < holdUntil {
                return
            }

            let next = self.speechLevel * 0.72
            if next < 0.02 {
                self.setSpeechLevel(0)
                self.stopSpeechLevelDecay()
            } else {
                self.setSpeechLevel(next)
            }
        }

        if let speechLevelDecayTimer {
            RunLoop.main.add(speechLevelDecayTimer, forMode: .common)
        }
    }

    private func stopSpeechLevelDecay() {
        speechLevelDecayTimer?.invalidate()
        speechLevelDecayTimer = nil
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
        cleanupAudioFile()
        if openAITTSSessionID != nil {
            playNextOpenAIChunkIfReady()
        } else {
            stopAudioMetering()
            setSpeaking(false)
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        stopAudioMetering()
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
        currentSpeechProcess?.terminate()
        currentSpeechProcess = nil
        stopOpenAIStreamPlayback()
        stopGeminiStreamPlayback()
        stopAudioMetering()
        stopSpeechLevelDecay()
        audioPlayer?.stop()
        audioPlayer = nil
        cleanupAudioFile()
        resetOpenAIChunkState()
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

    private func setSpeechLevel(_ value: CGFloat) {
        DispatchQueue.main.async {
            self.speechLevel = min(max(value, 0), 1)
        }
    }

    private func setSpeaking(_ value: Bool) {
        DispatchQueue.main.async {
            self.isSpeaking = value
            if !value {
                self.speechLevel = 0
            }
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

    private func xttsLanguageCode(for language: CompanionResponseLanguage) -> String {
        switch language {
        case .russian:
            return "ru"
        case .ukrainian:
            return "uk"
        case .english:
            return "en"
        }
    }

    private func speechChunks(for text: String) -> [String] {
        let nsRange = text.startIndex..<text.endIndex
        var sentences: [String] = []

        text.enumerateSubstrings(in: nsRange, options: [.bySentences, .substringNotRequired]) { _, range, _, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
        }

        if sentences.isEmpty {
            sentences = text
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        if sentences.isEmpty {
            return [text]
        }

        var chunks: [String] = []
        var currentChunk = ""
        var sentencesInChunk = 0

        for sentence in sentences {
            let candidate = currentChunk.isEmpty ? sentence : "\(currentChunk) \(sentence)"
            let shouldWrap = candidate.count > 180 || sentencesInChunk >= 2
            if shouldWrap && !currentChunk.isEmpty {
                chunks.append(currentChunk)
                currentChunk = sentence
                sentencesInChunk = 1
            } else {
                currentChunk = candidate
                sentencesInChunk += 1
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks
    }

    private static func extractOpenAIError(from data: Data) -> String {
        struct OpenAIErrorEnvelope: Decodable {
            struct APIError: Decodable {
                let message: String
            }

            let error: APIError
        }

        if let envelope = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data) {
            return envelope.error.message
        }

        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "OpenAI TTS вернул ошибку."
    }

    private func xttsPythonScript(outputPath: String, referencePath: String, text: String, languageCode: String) -> String {
        let escapedOutput = outputPath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedReference = referencePath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedText = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedLanguage = languageCode.replacingOccurrences(of: "\"", with: "\\\"")

        return """
from TTS.api import TTS

tts = TTS("tts_models/multilingual/multi-dataset/xtts_v2", gpu=False)
tts.tts_to_file(
    text=\"\(escapedText)\",
    file_path=\"\(escapedOutput)\",
    speaker_wav=\"\(escapedReference)\",
    language=\"\(escapedLanguage)\",
)
print("DONE")
"""
    }
}

enum OpenAITTSError: LocalizedError {
    case invalidResponse
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "OpenAI TTS вернул неожиданный ответ."
        case .serverMessage(let message):
            return message
        }
    }
}

private struct GeminiTTSStreamResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                struct InlineData: Decodable {
                    let data: String
                    let mimeType: String?
                }

                let inlineData: InlineData?
            }

            let parts: [Part]
        }

        let content: Content
    }

    let candidates: [Candidate]
}

private struct OpenAITTSStreamEvent: Decodable {
    let type: String
    let audio: String?
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
