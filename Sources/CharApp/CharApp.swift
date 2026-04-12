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
                        Text(model.displayName).tag(model.id)
                    }
                }
                .pickerStyle(.menu)

                Toggle(
                    "Озвучивать ответы",
                    isOn: Binding(
                        get: { viewModel.voiceRepliesEnabled },
                        set: { viewModel.setVoiceRepliesEnabled($0) }
                    )
                )

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
