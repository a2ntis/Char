import AppKit
import Carbon
import SwiftUI

@main
struct CharApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            CompanionSettingsView(viewModel: appDelegate.viewModel)
        }
        .commands {
            CommandMenu("Компаньон") {
                Button("Перенести сюда") {
                    appDelegate.bringCompanionHere()
                }
                .keyboardShortcut("h", modifiers: [.control, .option])
            }
        }
    }
}

struct CompanionSettingsView: View {
    @ObservedObject var viewModel: CompanionViewModel

    var body: some View {
        Form {
            Section("Компаньон") {
                Picker(
                    "Персонаж",
                    selection: Binding(
                        get: { viewModel.selectedModelID },
                        set: { viewModel.selectModel(id: $0) }
                    )
                ) {
                    ForEach(viewModel.availableModels) { model in
                        if model.isVRM0x {
                            Text("\(model.displayName) (VRM 0.x — не поддерж.)")
                                .foregroundStyle(.secondary)
                                .tag(model.id)
                        } else {
                            Text(model.displayName).tag(model.id)
                        }
                    }
                }
                .pickerStyle(.menu)

                if viewModel.selectedModel.isVRM0x {
                    Text("VRM 0.x не полностью поддерживается — позы и анимации могут отображаться некорректно. Экспортируй модель как VRM 1.0 из VRoid Studio.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Picker(
                    "Язык ответа",
                    selection: Binding(
                        get: { viewModel.profile.responseLanguage },
                        set: { viewModel.setResponseLanguage($0) }
                    )
                ) {
                    ForEach(CompanionResponseLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("Горячая клавиша") {
                    Text("⌃⌥H")
                        .foregroundStyle(.secondary)
                }

                Text("Размер аватара подстраивается под пропорции выбранной Live2D-модели.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Голос") {
                Toggle(
                    "Озвучивать ответы",
                    isOn: Binding(
                        get: { viewModel.voiceRepliesEnabled },
                        set: { viewModel.setVoiceRepliesEnabled($0) }
                    )
                )

                Picker(
                    "Провайдер озвучки",
                    selection: Binding(
                        get: { viewModel.profile.ttsProvider },
                        set: { viewModel.setTTSProvider($0) }
                    )
                ) {
                    ForEach(CompanionTTSProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)

                if viewModel.profile.ttsProvider == .system {
                    Text("Используется встроенный голос macOS. Язык берется из настройки ответа.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if viewModel.profile.ttsProvider == .piper {
                    TextField(
                        "Путь к Piper",
                        text: Binding(
                            get: { viewModel.piperExecutablePathText },
                            set: { viewModel.setPiperExecutablePath($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    HStack {
                        Text(viewModel.piperVoicesDirectoryText.isEmpty ? "Папка с голосами не выбрана" : viewModel.piperVoicesDirectoryText)
                            .lineLimit(2)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 12)

                        Button("Выбрать папку") {
                            viewModel.choosePiperVoicesDirectory()
                        }
                    }

                    if !viewModel.availablePiperVoices.isEmpty {
                        Picker(
                            "Найденные голоса",
                            selection: Binding(
                                get: { viewModel.profile.piperModelPath },
                                set: { viewModel.selectPiperVoice($0) }
                            )
                        ) {
                            ForEach(viewModel.availablePiperVoices) { voice in
                                Text(voice.displayName).tag(voice.modelPath)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Text("Piper ожидает локальный бинарник и голосовую модель `.onnx`.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text(viewModel.piperStatusSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Button("Подставить локальный Piper") {
                            viewModel.autofillPiperPaths()
                        }

                        Button("Обновить список голосов") {
                            viewModel.refreshPiperVoices()
                        }

                        Button(viewModel.isInstallingPiper ? "Устанавливаю..." : "Установить Piper автоматически") {
                            Task { await viewModel.installPiperAutomatically() }
                        }
                        .disabled(viewModel.isInstallingPiper)
                    }
                } else if viewModel.profile.ttsProvider == .xtts {
                    TextField(
                        "Путь к XTTS Python",
                        text: Binding(
                            get: { viewModel.xttsPythonPathText },
                            set: { viewModel.setXTTSPythonPath($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    HStack {
                        Text(viewModel.xttsReferencesDirectoryText.isEmpty ? "Папка с референсами не выбрана" : viewModel.xttsReferencesDirectoryText)
                            .lineLimit(2)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 12)

                        Button("Выбрать папку") {
                            viewModel.chooseXTTSReferencesDirectory()
                        }
                    }

                    if !viewModel.availableXTTSReferences.isEmpty {
                        Picker(
                            "Найденные референсы",
                            selection: Binding(
                                get: { viewModel.profile.xttsReferencePath },
                                set: { viewModel.selectXTTSReference($0) }
                            )
                        ) {
                            ForEach(viewModel.availableXTTSReferences) { reference in
                                Text(reference.displayName).tag(reference.filePath)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Text("XTTS использует reference clip для клонирования голоса. Лучше всего работает 6-10 секунд чистой речи.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text(viewModel.xttsStatusSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Button("Подставить локальный XTTS") {
                            viewModel.autofillXTTSPaths()
                        }

                        Button("Обновить список референсов") {
                            viewModel.refreshXTTSReferences()
                        }
                    }
                } else if viewModel.profile.ttsProvider == .openAI {
                    Picker(
                        "Модель OpenAI TTS",
                        selection: Binding(
                            get: { viewModel.profile.openAITTSModel },
                            set: { viewModel.setOpenAITTSModel($0) }
                        )
                    ) {
                        ForEach(OpenAITTSCatalog.supportedModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker(
                        "Голос",
                        selection: Binding(
                            get: { viewModel.profile.openAITTSVoice },
                            set: { viewModel.setOpenAITTSVoice($0) }
                        )
                    ) {
                        ForEach(viewModel.availableOpenAITTSVoices, id: \.self) { voice in
                            Text(voice).tag(voice)
                        }
                    }
                    .pickerStyle(.menu)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Скорость")
                            Spacer()
                            Text(String(format: "%.2f", viewModel.profile.openAITTSSpeed))
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: Binding(
                                get: { viewModel.profile.openAITTSSpeed },
                                set: { viewModel.setOpenAITTSSpeed($0) }
                            ),
                            in: 0.6...1.2,
                            step: 0.02
                        )
                    }

                    TextField(
                        "Endpoint OpenAI TTS",
                        text: Binding(
                            get: { viewModel.openAITTSEndpointText },
                            set: { viewModel.setOpenAITTSEndpoint($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Инструкции для голоса")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        TextEditor(
                            text: Binding(
                                get: { viewModel.openAITTSInstructionsText },
                                set: { viewModel.setOpenAITTSInstructions($0) }
                            )
                        )
                        .frame(minHeight: 96)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.black.opacity(0.12), lineWidth: 1)
                        )
                    }

                    Text("Для аниме-вайба обычно лучше начинать с более легких женских голосов вроде coral или shimmer, со скоростью около 0.9-1.0 и мягкими friendly-инструкциями.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text(viewModel.openAITTSStatusSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    SecureField(
                        "Gemini API Key",
                        text: Binding(
                            get: { viewModel.googleTTSAPIKey },
                            set: { viewModel.setGoogleTTSAPIKey($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    TextField(
                        "Endpoint Gemini API",
                        text: Binding(
                            get: { viewModel.googleTTSEndpointText },
                            set: { viewModel.setGoogleTTSEndpoint($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Picker(
                        "Модель Gemini TTS",
                        selection: Binding(
                            get: { viewModel.profile.googleTTSModel },
                            set: { viewModel.setGoogleTTSModel($0) }
                        )
                    ) {
                        ForEach(GeminiTTSCatalog.supportedModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)

                    if !viewModel.filteredGoogleTTSVoices.isEmpty {
                        Picker(
                            "Голос Gemini",
                            selection: Binding(
                                get: { viewModel.profile.googleTTSVoiceName },
                                set: { viewModel.setGoogleTTSVoiceName($0) }
                            )
                        ) {
                            ForEach(viewModel.filteredGoogleTTSVoices) { voice in
                                Text(voice.displayName).tag(voice.name)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Инструкции для голоса")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        TextEditor(
                            text: Binding(
                                get: { viewModel.googleTTSStyleInstructionsText },
                                set: { viewModel.setGoogleTTSStyleInstructions($0) }
                            )
                        )
                        .frame(minHeight: 96)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.black.opacity(0.12), lineWidth: 1)
                        )
                    }

                    Text("У Gemini TTS стиль лучше задавать текстом: мягкий, youthful, warm, conversational. Голос и prompt тут важнее, чем numeric-крутилки.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("Для минимальной задержки лучше начинать с `gemini-2.5-flash-lite-preview-tts`. Более тяжелые модели обычно звучат богаче, но стартуют медленнее.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text(viewModel.googleTTSStatusSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("Обновить каталог голосов Gemini") {
                        Task { await viewModel.refreshGoogleTTSVoices() }
                    }
                }

                Button("Пробный голос") {
                    viewModel.previewVoice()
                }
            }

            Section("LLM") {
                Picker(
                    "Провайдер",
                    selection: Binding(
                        get: { viewModel.profile.provider },
                        set: { viewModel.setProvider($0) }
                    )
                ) {
                    ForEach(CompanionLLMProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)

                if viewModel.profile.provider == .ollama {
                    if !viewModel.availableLLMModels.isEmpty {
                        Picker(
                            "Локальная модель",
                            selection: Binding(
                                get: { viewModel.profile.ollamaModel },
                                set: { viewModel.setActiveLLMModel($0) }
                            )
                        ) {
                            ForEach(viewModel.availableLLMModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                    } else {
                        TextField(
                            "Модель Ollama",
                            text: Binding(
                                get: { viewModel.profile.ollamaModel },
                                set: { viewModel.setActiveLLMModel($0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    TextField(
                        "Endpoint Ollama",
                        text: Binding(
                            get: { viewModel.ollamaEndpointText },
                            set: { viewModel.setActiveEndpoint($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    HStack {
                        Button(viewModel.isRefreshingLLMModels ? "Обновляю..." : "Обновить список моделей") {
                            Task { await viewModel.refreshLLMModels() }
                        }
                        .disabled(viewModel.isRefreshingLLMModels)

                        Button("Проверить подключение") {
                            Task { await viewModel.validateLLMConnection() }
                        }
                        .disabled(viewModel.isRefreshingLLMModels)

                        if !viewModel.availableLLMModels.isEmpty {
                            Text("\(viewModel.availableLLMModels.count) найдено")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if viewModel.profile.provider == .openAI {
                    if !viewModel.availableOpenAIModels.isEmpty {
                        Picker(
                            "Модель OpenAI",
                            selection: Binding(
                                get: { viewModel.profile.openAIModel },
                                set: { viewModel.setActiveLLMModel($0) }
                            )
                        ) {
                            ForEach(viewModel.availableOpenAIModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                    } else {
                        Text("Список моделей появится после успешного запроса к OpenAI.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    TextField(
                        "Endpoint OpenAI",
                        text: Binding(
                            get: { viewModel.openAIEndpointText },
                            set: { viewModel.setActiveEndpoint($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    SecureField(
                        "OpenAI API Key",
                        text: Binding(
                            get: { viewModel.openAIAPIKey },
                            set: { viewModel.setOpenAIAPIKey($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    HStack {
                        Button(viewModel.isRefreshingLLMModels ? "Обновляю..." : "Обновить список OpenAI моделей") {
                            Task { await viewModel.refreshLLMModels() }
                        }
                        .disabled(viewModel.isRefreshingLLMModels)

                        Button("Проверить подключение") {
                            Task { await viewModel.validateLLMConnection() }
                        }
                        .disabled(viewModel.isRefreshingLLMModels)

                        Text("Показываются только модели, которые реально доступны этому ключу.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if !viewModel.availableLMStudioModels.isEmpty {
                        Picker(
                            "Модель LM Studio",
                            selection: Binding(
                                get: { viewModel.profile.lmStudioModel },
                                set: { viewModel.setActiveLLMModel($0) }
                            )
                        ) {
                            ForEach(viewModel.availableLMStudioModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                    } else {
                        TextField(
                            "Модель LM Studio",
                            text: Binding(
                                get: { viewModel.profile.lmStudioModel },
                                set: { viewModel.setActiveLLMModel($0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    TextField(
                        "Endpoint LM Studio",
                        text: Binding(
                            get: { viewModel.lmStudioEndpointText },
                            set: { viewModel.setActiveEndpoint($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    HStack {
                        Button(viewModel.isRefreshingLLMModels ? "Обновляю..." : "Обновить список LM Studio моделей") {
                            Task { await viewModel.refreshLLMModels() }
                        }
                        .disabled(viewModel.isRefreshingLLMModels)

                        Button("Проверить подключение") {
                            Task { await viewModel.validateLLMConnection() }
                        }
                        .disabled(viewModel.isRefreshingLLMModels)

                        Text("Ожидается локальный OpenAI-compatible сервер LM Studio.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !viewModel.status.isEmpty {
                    Text(viewModel.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Тест эмоций") {
                Text("Сначала удобно проверить конкретные expression-файлы, а уже потом маппинг happy/shy/thinking.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Auto") {
                        viewModel.clearManualPreview()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(!viewModel.isManualPreviewMode ? .pink : .gray.opacity(0.7))

                    emotionButton("Happy", emotion: .happy)
                    emotionButton("Excited", emotion: .excited)
                    emotionButton("Angry", emotion: .angry)
                }

                HStack(spacing: 8) {
                    emotionButton("Shy", emotion: .shy)
                    emotionButton("Thinking", emotion: .thinking)
                    emotionButton("Sleepy", emotion: .sleepy)
                }

                if !viewModel.selectedModel.expressions.isEmpty {
                    Text("Точные выражения текущей модели")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible(minimum: 120), spacing: 8),
                            GridItem(.flexible(minimum: 120), spacing: 8)
                        ], spacing: 8) {
                            ForEach(viewModel.selectedModel.expressions) { expression in
                                Button(expression.displayName) {
                                    viewModel.previewExpression(expression)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 150)
                }

                if !viewModel.selectedModel.preset.extraEmotionButtons.isEmpty {
                    Text("Быстрые эмоции модели")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [
                        GridItem(.flexible(minimum: 120), spacing: 8),
                        GridItem(.flexible(minimum: 120), spacing: 8)
                    ], spacing: 8) {
                        ForEach(viewModel.selectedModel.preset.extraEmotionButtons) { button in
                            Button(button.label) {
                                viewModel.previewExpression(
                                    CompanionExpressionOption(
                                        id: button.id,
                                        displayName: button.label,
                                        triggerHints: button.hints
                                    )
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange.opacity(0.8))
                        }
                    }
                }

                if !viewModel.selectedModel.motionGroups.isEmpty {
                    Text("Анимации текущей модели")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [
                        GridItem(.flexible(minimum: 120), spacing: 8),
                        GridItem(.flexible(minimum: 120), spacing: 8)
                    ], spacing: 8) {
                        ForEach(viewModel.selectedModel.motionGroups) { motionGroup in
                            Button("\(motionGroup.displayName) (\(motionGroup.motionCount))") {
                                viewModel.previewMotionGroup(motionGroup)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                if viewModel.selectedModel.runtime == .vrm && !viewModel.availablePoses.isEmpty {
                    Text("Позы (.vroidpose)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [
                        GridItem(.flexible(minimum: 120), spacing: 8),
                        GridItem(.flexible(minimum: 120), spacing: 8)
                    ], spacing: 8) {
                        ForEach(viewModel.availablePoses) { pose in
                            Button(pose.displayName) {
                                viewModel.previewPose(pose)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple.opacity(0.75))
                        }
                    }
                }

                if viewModel.selectedModel.runtime == .vrm && !viewModel.availableVRMAAnimations.isEmpty {
                    Text("VRM анимации (.vrma)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [
                        GridItem(.flexible(minimum: 120), spacing: 8),
                        GridItem(.flexible(minimum: 120), spacing: 8)
                    ], spacing: 8) {
                        ForEach(viewModel.availableVRMAAnimations) { animation in
                            Button(animation.displayName) {
                                viewModel.previewVRMA(animation)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.teal.opacity(0.85))
                        }
                    }
                }

                if viewModel.selectedModel.runtime == .vrm && !viewModel.availableBVHAnimations.isEmpty {
                    Text("BVH анимации (.bvh)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [
                        GridItem(.flexible(minimum: 120), spacing: 8),
                        GridItem(.flexible(minimum: 120), spacing: 8)
                    ], spacing: 8) {
                        ForEach(viewModel.availableBVHAnimations) { animation in
                            Button(animation.displayName) {
                                viewModel.previewBVH(animation)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.cyan.opacity(0.85))
                        }
                    }
                }

                if viewModel.selectedModel.runtime == .vrm {
                    Text("Базовые VRM выражения")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [
                        GridItem(.flexible(minimum: 120), spacing: 8),
                        GridItem(.flexible(minimum: 120), spacing: 8)
                    ], spacing: 8) {
                        ForEach(CompanionVRMExpressionPreset.allCases) { expression in
                            Button(expression.displayName) {
                                viewModel.previewVRMExpression(expression)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.mint.opacity(0.85))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520, height: 520)
    }

    private func emotionButton(_ title: String, emotion: CompanionEmotionState?) -> some View {
        Button(title) {
            viewModel.previewEmotion(emotion)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.manualEmotionOverride == emotion ? .pink : .gray.opacity(0.7))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = CompanionViewModel()
    private var coordinator: CompanionWindowCoordinator?
    private var globalHotKeyRef: EventHotKeyRef?
    private var globalHotKeyHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        coordinator = CompanionWindowCoordinator(viewModel: viewModel)
        coordinator?.show()
        registerBringHereHotKey()
        viewModel.boot()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func bringCompanionHere() {
        coordinator?.bringCompanionToMouseScreen()
    }

    private func registerBringHereHotKey() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            bringCompanionHotKeyHandler,
            1,
            &eventSpec,
            userData,
            &globalHotKeyHandler
        )

        let hotKeyID = EventHotKeyID(signature: bringCompanionHotKeySignature, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_H),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &globalHotKeyRef
        )
    }

    fileprivate nonisolated func handleBringHereHotKey(_ event: EventRef?) -> OSStatus {
        guard let event else { return noErr }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr,
              hotKeyID.signature == bringCompanionHotKeySignature,
              hotKeyID.id == 1 else {
            return noErr
        }

        Task { @MainActor [weak self] in
            self?.bringCompanionHere()
        }
        return noErr
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalHotKeyRef {
            UnregisterEventHotKey(globalHotKeyRef)
            self.globalHotKeyRef = nil
        }
        if let globalHotKeyHandler {
            RemoveEventHandler(globalHotKeyHandler)
            self.globalHotKeyHandler = nil
        }
    }
}

private let bringCompanionHotKeySignature: OSType = 0x43484152 // CHAR

private func bringCompanionHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
    return delegate.handleBringHereHotKey(event)
}
