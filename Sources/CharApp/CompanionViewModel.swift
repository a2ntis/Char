import Foundation
import CoreGraphics
import Combine

@MainActor
final class CompanionViewModel: ObservableObject {
    private enum DefaultsKey {
        static let selectedModelID = "selectedCompanionModelID"
        static let avatarZoom = "companionAvatarZoom"
    }

    @Published var messages: [ChatMessage]
    @Published var draft: String = ""
    @Published var isSending = false
    @Published var status = ""
    @Published var voiceRepliesEnabled = true
    @Published var panelExpanded = true
    @Published var isBubbleVisible = false
    @Published var profile = CompanionProfile()
    @Published var availableModels: [CompanionModelOption]
    @Published var selectedModelID: String
    @Published var avatarAspectRatio: CGFloat
    @Published var avatarZoom: CGFloat
    @Published var presenceState: CompanionPresenceState = .idle
    @Published var emotionState: CompanionEmotionState = .neutral
    @Published var isAvatarDragging = false
    @Published var manualEmotionOverride: CompanionEmotionState?
    @Published var isManualPreviewMode = false
    @Published var manualExpressionRequest: CompanionExpressionRequest?
    @Published var manualMotionRequest: CompanionMotionRequest?

    let speech = SpeechCoordinator()

    private let client = OllamaClient()
    private var cancellables: Set<AnyCancellable> = []
    private var emotionResetTask: Task<Void, Never>?
    private var dragResetTask: Task<Void, Never>?

    init() {
        let assetsRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets")
        let discoveredModels = ModelCatalog.discoverModels(in: assetsRoot)
        let fallbackModel = CompanionModelOption(
            id: assetsRoot.appendingPathComponent("shizuku/runtime").path,
            displayName: "Shizuku",
            assetRootPath: assetsRoot.appendingPathComponent("shizuku/runtime").path,
            preset: CompanionModelPreset(passiveIdle: true),
            expressions: [],
            motionGroups: []
        )
        let initialModels = discoveredModels.isEmpty ? [fallbackModel] : discoveredModels

        availableModels = initialModels
        let savedModelID = UserDefaults.standard.string(forKey: DefaultsKey.selectedModelID)
        selectedModelID = initialModels.first(where: { $0.id == savedModelID })?.id ?? initialModels[0].id
        avatarAspectRatio = 0.86
        let savedZoom = CGFloat(UserDefaults.standard.double(forKey: DefaultsKey.avatarZoom))
        avatarZoom = savedZoom > 0 ? min(max(savedZoom, 0.6), 2.4) : 1.0
        messages = [
            ChatMessage(
                role: .system,
                text: CompanionProfile().persona
            ),
            ChatMessage(
                role: .assistant,
                text: "Привет. Я рядом."
            )
        ]

        bindPresence()
    }

    func boot() {
        status = ""
    }

    var selectedModel: CompanionModelOption {
        availableModels.first(where: { $0.id == selectedModelID }) ?? availableModels[0]
    }

    var avatarLayout: AvatarLayout {
        let normalizedAspect = min(max(avatarAspectRatio, 0.45), 1.8)
        let targetArea: CGFloat = 56_000
        var modelWidth = sqrt(targetArea * normalizedAspect)
        var modelHeight = modelWidth / normalizedAspect

        modelWidth = min(max(modelWidth, 180), 380)
        modelHeight = min(max(modelHeight, 220), 320)

        modelWidth *= avatarZoom
        modelHeight *= avatarZoom

        modelWidth = min(max(modelWidth, 150), 780)
        modelHeight = min(max(modelHeight, 180), 900)

        let viewport = CGSize(width: modelWidth, height: modelHeight)
        return AvatarLayout(
            viewportSize: viewport,
            panelSize: CGSize(width: modelWidth + 28, height: modelHeight + 42)
        )
    }

    func updateAvatarAspectRatio(_ ratio: CGFloat) {
        let normalized = min(max(ratio, 0.45), 1.8)
        if abs(normalized - avatarAspectRatio) > 0.01 {
            avatarAspectRatio = normalized
        }
    }

    func adjustAvatarZoom(byScrollDelta deltaY: CGFloat) {
        guard deltaY != 0 else { return }

        let step = deltaY > 0 ? 1.08 : (1.0 / 1.08)
        let newZoom = min(max(avatarZoom * step, 0.6), 2.4)
        guard abs(newZoom - avatarZoom) > 0.001 else { return }
        avatarZoom = newZoom
        UserDefaults.standard.set(Double(newZoom), forKey: DefaultsKey.avatarZoom)
    }

    func selectModel(id: String) {
        guard selectedModelID != id else { return }
        clearManualPreview()
        selectedModelID = id
        UserDefaults.standard.set(id, forKey: DefaultsKey.selectedModelID)
    }

    func sendCurrentDraft() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        draft = ""
        await send(text: trimmed)
    }

    func send(text: String) async {
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        updatePresence()

        messages.append(ChatMessage(role: .user, text: text))

        do {
            let reply = try await client.send(messages: messages, profile: profile)
            messages.append(ChatMessage(role: .assistant, text: reply))
            setEmotion(for: reply)
            if voiceRepliesEnabled {
                speech.speak(reply)
            } else {
                presenceState = .speaking
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2.4))
                    await MainActor.run {
                        self?.updatePresence()
                    }
                }
            }
        } catch {
            messages.append(ChatMessage(role: .assistant, text: "Я сейчас немного задумалась и не смогла ответить. Попробуй еще раз через секунду."))
        }

        isSending = false
        updatePresence()
    }

    func toggleListening() async {
        if !speech.canUseSpeechInput {
            speech.warmUp()
        }

        await speech.toggleListening { [weak self] text in
            guard let self else { return }
            await self.send(text: text)
        }
    }

    var visibleMessages: [ChatMessage] {
        messages.filter { $0.role != .system }
    }

    func pulseDragging() {
        dragResetTask?.cancel()
        isAvatarDragging = true
        dragResetTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            await MainActor.run {
                self?.isAvatarDragging = false
            }
        }
    }

    func previewEmotion(_ emotion: CompanionEmotionState?) {
        emotionResetTask?.cancel()
        isManualPreviewMode = emotion != nil
        manualEmotionOverride = emotion
        emotionState = emotion ?? .neutral
    }

    func previewExpression(_ expression: CompanionExpressionOption) {
        emotionResetTask?.cancel()
        isManualPreviewMode = true
        manualEmotionOverride = nil
        manualExpressionRequest = CompanionExpressionRequest(
            label: expression.displayName,
            hints: expression.triggerHints
        )
    }

    func previewMotionGroup(_ motionGroup: CompanionMotionGroupOption) {
        isManualPreviewMode = true
        manualMotionRequest = CompanionMotionRequest(groupName: motionGroup.groupName)
    }

    func clearManualPreview() {
        emotionResetTask?.cancel()
        isManualPreviewMode = false
        manualEmotionOverride = nil
        emotionState = .neutral
        manualExpressionRequest = nil
        manualMotionRequest = nil
    }

    private func bindPresence() {
        speech.$isListening
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updatePresence()
            }
            .store(in: &cancellables)

        speech.$isSpeaking
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updatePresence()
            }
            .store(in: &cancellables)
    }

    private func updatePresence() {
        if speech.isListening {
            presenceState = .listening
        } else if speech.isSpeaking {
            presenceState = .speaking
        } else if isSending {
            presenceState = .thinking
        } else {
            presenceState = .idle
        }
    }

    private func setEmotion(for text: String) {
        guard !isManualPreviewMode else { return }
        emotionResetTask?.cancel()
        emotionState = detectEmotion(from: text)

        emotionResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4.5))
            await MainActor.run {
                self?.emotionState = .neutral
            }
        }
    }

    private func detectEmotion(from text: String) -> CompanionEmotionState {
        let lowercased = text.lowercased()

        if text.contains("😠") || text.contains("😡") || text.contains("💢") {
            return .angry
        }

        if text.contains("😴") || text.contains("🥱") {
            return .sleepy
        }

        if text.contains("🤔") || text.contains("🧐") || text.contains("❓") {
            return .thinking
        }

        if text.contains("😳") || text.contains("🙈") || text.contains("🥺") || text.contains("💦") {
            return .shy
        }

        if text.contains("😮") || text.contains("😲") || text.contains("😱") || text.contains("🤯") || text.contains("⚡") || text.contains("💥") {
            return .excited
        }

        if text.contains("😊") || text.contains("☺️") || text.contains("🥰") || text.contains("😍") || text.contains("❤") || text.contains("❤️") || text.contains("💖") || text.contains("🌈") || text.contains("🎉") {
            return .happy
        }

        if lowercased.contains("сон") || lowercased.contains("спать") || lowercased.contains("устала") || lowercased.contains("устал") || lowercased.contains(" sleepy") {
            return .sleepy
        }

        if lowercased.contains("дума") || lowercased.contains("размыш") || lowercased.contains("хмм") || lowercased.contains("hmm") || lowercased.contains("confused") || text.contains("?") {
            return .thinking
        }

        if lowercased.contains("смущ") || lowercased.contains("волн") || lowercased.contains("извини") || lowercased.contains("прости") || lowercased.contains(" embarrassed") {
            return .shy
        }

        if lowercased.contains("зл") || lowercased.contains("серд") || lowercased.contains("angry") || lowercased.contains("mad") {
            return .angry
        }

        if lowercased.contains("удив") || lowercased.contains("ой") || lowercased.contains("что это") || lowercased.contains("шок") || lowercased.contains("страх") || lowercased.contains("нет-нет") {
            return .excited
        }

        if lowercased.contains("ура") || lowercased.contains("yay") || lowercased.contains("вау") || lowercased.contains("класс") || lowercased.contains("счаст") || text.contains("!!") {
            return .excited
        }

        if lowercased.contains("груст") || lowercased.contains("печаль") || lowercased.contains("sad") {
            return .shy
        }

        if lowercased.contains("рада") || lowercased.contains("люб") || lowercased.contains("ня") || lowercased.contains("hehe") || lowercased.contains("smile") || lowercased.contains("счастлив") {
            return .happy
        }

        return .neutral
    }
}

struct CompanionExpressionRequest: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let hints: [String]
}

struct CompanionMotionRequest: Identifiable, Equatable {
    let id = UUID()
    let groupName: String
}
