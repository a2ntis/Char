import AppKit
import Combine
import Live2DBridge
import SwiftUI

struct AvatarPanelView: View {
    @ObservedObject var viewModel: CompanionViewModel
    let onToggleChat: () -> Void

    @State private var avatarScale = 0.98
    @State private var blink = false

    var body: some View {
        VStack(spacing: 8) {
            if !viewModel.isBubbleVisible {
                Text("Tap \(viewModel.selectedModel.displayName)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.74))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.78), in: Capsule())
                    .transition(.opacity)
            }

            Live2DAvatarRepresentable(
                assetRootPath: viewModel.selectedModel.assetRootPath,
                passiveIdle: viewModel.selectedModel.preset.passiveIdle,
                onTap: onToggleChat
            ) { aspectRatio in
                viewModel.updateAvatarAspectRatio(aspectRatio)
            }
                .scaleEffect(avatarScale)
                .frame(
                    width: viewModel.avatarLayout.viewportSize.width,
                    height: viewModel.avatarLayout.viewportSize.height
                )
                .shadow(color: .pink.opacity(0.28), radius: 26, y: 14)
        }
        .frame(
            width: viewModel.avatarLayout.panelSize.width,
            height: viewModel.avatarLayout.panelSize.height,
            alignment: .bottom
        )
        .background(Color.clear)
        .onAppear {
            runIdleAnimation()
            runBlinkLoop()
        }
    }

    private func runIdleAnimation() {
        withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
            avatarScale = 1.02
        }
    }

    private func runBlinkLoop() {
        Task {
            while true {
                try? await Task.sleep(for: .seconds(3.1))
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.08)) {
                        blink = true
                    }
                }
                try? await Task.sleep(for: .seconds(0.12))
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        blink = false
                    }
                }
            }
        }
    }
}

struct BubblePanelView: View {
    @ObservedObject var viewModel: CompanionViewModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .center, spacing: 14) {
            ScrollViewReader { proxy in
                transcriptContainer
                .onChange(of: viewModel.visibleMessages.count) {
                    if let last = viewModel.visibleMessages.last {
                        withAnimation(.smooth(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            inputBar
        }
        .padding(14)
        .frame(width: 382, height: 338, alignment: .top)
        .background(Color.clear)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                inputFocused = true
            }
        }
    }

    private var transcriptContainer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.white.opacity(0.68))
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.black.opacity(0.92), lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
                .overlay(alignment: .topLeading) {
                    MangaToneOverlay()
                        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                }

            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(viewModel.visibleMessages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 22)
            }
            .frame(width: 332, height: 214)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                TextField("Напиши мне реплику…", text: $viewModel.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1 ... 4)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .tint(.white)
                    .padding(.leading, 18)
                    .padding(.trailing, 52)
                    .padding(.vertical, 13)
                    .frame(width: 276, alignment: .leading)
                    .frame(minHeight: 68)
                    .fixedSize(horizontal: false, vertical: true)
                    .focused($inputFocused)
                    .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1.2)
                    }
                    .onSubmit {
                        Task { await viewModel.sendCurrentDraft() }
                    }

                Button {
                    Task { await viewModel.toggleListening() }
                } label: {
                    Image(systemName: viewModel.speech.isListening ? "waveform.circle.fill" : "mic.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            (viewModel.speech.isListening ? Color(red: 0.72, green: 0.18, blue: 0.30).opacity(0.9) : Color.clear),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
            }

            Spacer(minLength: 54)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum CompanionExpression {
    case idle
    case happy
    case listening
    case talking
}

private struct CompanionExpressionKey: EnvironmentKey {
    static let defaultValue: CompanionExpression = .idle
}

extension EnvironmentValues {
    var companionExpression: CompanionExpression {
        get { self[CompanionExpressionKey.self] }
        set { self[CompanionExpressionKey.self] = newValue }
    }
}

struct AvatarView: View {
    let isBlinking: Bool
    @Environment(\.companionExpression) private var expression

    var body: some View {
        ZStack {
            backgroundAura
            starAccents

            VStack(spacing: 0) {
                ZStack {
                    hairBack
                    hairBuns

                    face
                    bangs

                    HStack(spacing: 28) {
                        eye
                        eye
                    }
                    .offset(y: expression == .happy ? 8 : 10)

                    eyebrows

                    mouth

                    accessory

                    HStack {
                        blush
                        Spacer()
                        blush
                    }
                    .frame(width: 84)
                    .offset(y: 34)
                }

                bodyShape
                    .offset(y: -10)
            }
        }
    }

    private var eye: some View {
        Group {
            if isBlinking {
                Capsule()
                    .fill(Color(red: 0.30, green: 0.18, blue: 0.26))
                    .frame(width: expression == .happy ? 22 : 20, height: 4)
            } else {
                ZStack {
                    Capsule()
                        .fill(.white)
                        .frame(width: 24, height: 17)
                    Circle()
                        .fill(eyeColor)
                        .frame(width: expression == .listening ? 13 : 11, height: expression == .listening ? 13 : 11)
                    Circle()
                        .fill(.white.opacity(0.8))
                        .frame(width: 4, height: 4)
                        .offset(x: -2, y: -2)
                }
            }
        }
    }

    private var backgroundAura: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.92),
                            Color(red: 1.0, green: 0.80, blue: 0.87)
                        ],
                        center: .top,
                        startRadius: 20,
                        endRadius: 130
                    )
                )
                .frame(width: 214, height: 214)

            Circle()
                .stroke(Color.white.opacity(0.45), lineWidth: 10)
                .frame(width: 178, height: 178)
                .blur(radius: 2)
        }
    }

    private var starAccents: some View {
        ZStack {
            sparkle
                .offset(x: -62, y: -56)
            sparkle
                .scaleEffect(0.7)
                .offset(x: 74, y: -18)
            sparkle
                .scaleEffect(0.55)
                .offset(x: -82, y: 22)
        }
    }

    private var sparkle: some View {
        Image(systemName: "sparkle")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.72))
    }

    private var hairBack: some View {
        RoundedRectangle(cornerRadius: 72, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.28, green: 0.10, blue: 0.23),
                        Color(red: 0.50, green: 0.18, blue: 0.36),
                        Color(red: 0.74, green: 0.38, blue: 0.53)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 168, height: 126)
            .offset(y: -26)
    }

    private var hairBuns: some View {
        HStack(spacing: 88) {
            Circle().fill(Color(red: 0.42, green: 0.16, blue: 0.31)).frame(width: 34, height: 34)
            Circle().fill(Color(red: 0.42, green: 0.16, blue: 0.31)).frame(width: 34, height: 34)
        }
        .offset(y: -46)
    }

    private var bangs: some View {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.34, green: 0.12, blue: 0.28),
                        Color(red: 0.68, green: 0.30, blue: 0.48)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 110, height: 30)
            .offset(y: -14)
    }

    private var face: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.92, blue: 0.88),
                        Color(red: 0.99, green: 0.86, blue: 0.80)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 134, height: 146)
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.35), lineWidth: 2)
                    .blur(radius: 1)
            }
            .offset(y: 14)
    }

    private var eyebrows: some View {
        HStack(spacing: 34) {
            eyebrow
            eyebrow
        }
        .offset(y: expression == .happy ? -10 : -8)
    }

    private var eyebrow: some View {
        Capsule()
            .fill(Color(red: 0.36, green: 0.17, blue: 0.28))
            .frame(width: 18, height: 3)
            .rotationEffect(.degrees(expression == .listening ? 8 : 0))
    }

    private var mouth: some View {
        Group {
            switch expression {
            case .talking:
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 0.78, green: 0.30, blue: 0.49))
                    .frame(width: 24, height: 18)
            case .happy:
                ArcSmile()
                    .stroke(Color(red: 0.78, green: 0.30, blue: 0.49), lineWidth: 4)
                    .frame(width: 24, height: 14)
            case .listening:
                Capsule()
                    .fill(Color(red: 0.86, green: 0.45, blue: 0.60))
                    .frame(width: 16, height: 8)
            case .idle:
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.82, green: 0.38, blue: 0.56))
                    .frame(width: 28, height: 10)
            }
        }
        .offset(y: 46)
    }

    private var accessory: some View {
        HStack(spacing: 68) {
            accessoryBow
            accessoryBow
        }
        .offset(y: -2)
    }

    private var accessoryBow: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(red: 1.0, green: 0.88, blue: 0.92))
                .frame(width: 18, height: 10)
            Circle()
                .fill(Color(red: 0.91, green: 0.54, blue: 0.67))
                .frame(width: 6, height: 6)
        }
    }

    private var blush: some View {
        Circle()
            .fill(Color(red: 1.0, green: 0.70, blue: 0.82).opacity(expression == .happy ? 0.95 : 0.72))
            .frame(width: expression == .happy ? 16 : 18, height: expression == .happy ? 10 : 10)
    }

    private var bodyShape: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.97, blue: 1.0),
                            Color(red: 0.87, green: 0.90, blue: 0.99)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 126, height: 86)

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.91, green: 0.68, blue: 0.77))
                .frame(width: 56, height: 8)
                .offset(y: 28)
        }
    }

    private var eyeColor: Color {
        switch expression {
        case .listening:
            return Color(red: 0.20, green: 0.42, blue: 0.62)
        case .happy:
            return Color(red: 0.52, green: 0.18, blue: 0.42)
        case .talking:
            return Color(red: 0.40, green: 0.17, blue: 0.36)
        case .idle:
            return Color(red: 0.40, green: 0.17, blue: 0.36)
        }
    }
}

struct ArcSmile: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.45),
            radius: rect.width * 0.28,
            startAngle: .degrees(20),
            endAngle: .degrees(160),
            clockwise: false
        )
        return path
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: message.role == .assistant ? .leading : .trailing, spacing: 4) {
            if message.role == .user {
                Text("Ты")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.45))
            }

            Text(message.text)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.black.opacity(0.9))
                .textSelection(.enabled)
                .multilineTextAlignment(message.role == .assistant ? .leading : .trailing)
                .frame(maxWidth: .infinity, alignment: message.role == .assistant ? .leading : .trailing)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MangaToneOverlay: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 16
            let radius: CGFloat = 1.15
            for x in stride(from: 20 as CGFloat, to: size.width * 0.55, by: spacing) {
                for y in stride(from: 18 as CGFloat, to: size.height * 0.45, by: spacing) {
                    let alpha = max(0.02, 0.09 - ((x + y) / (size.width + size.height)) * 0.08)
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                        with: .color(.black.opacity(alpha))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.minX + 3, y: rect.midY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - 4, y: rect.midY)
        )
        path.closeSubpath()
        return path
    }
}

struct Live2DAvatarRepresentable: NSViewRepresentable {
    let assetRootPath: String
    let passiveIdle: Bool
    let onTap: () -> Void
    let onAspectRatioChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let container = Live2DTappableContainer(
            assetRootPath: assetRootPath,
            passiveIdle: passiveIdle,
            onTap: onTap,
            onAspectRatioChange: onAspectRatioChange
        )
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let container = nsView as? Live2DTappableContainer else { return }
        container.configure(assetRootPath: assetRootPath, passiveIdle: passiveIdle, onAspectRatioChange: onAspectRatioChange)
    }
}

final class Live2DTappableContainer: NSView {
    private let live2d: CompanionLive2DView
    private let onTap: () -> Void
    private var currentAssetRootPath: String
    private var currentPassiveIdle: Bool

    init(assetRootPath: String, passiveIdle: Bool, onTap: @escaping () -> Void, onAspectRatioChange: @escaping (CGFloat) -> Void) {
        live2d = CompanionLive2DView(frame: NSRect(x: 0, y: 0, width: 208, height: 262))
        self.onTap = onTap
        currentAssetRootPath = assetRootPath
        currentPassiveIdle = passiveIdle
        super.init(frame: .zero)
        live2d.assetRootPath = assetRootPath
        live2d.passiveIdle = passiveIdle
        live2d.emotionExpressionMap = [:]
        live2d.autoresizingMask = [.width, .height]
        live2d.frame = bounds
        live2d.modelAspectRatioHandler = { aspectRatio in
            DispatchQueue.main.async {
                onAspectRatioChange(aspectRatio)
            }
        }
        addSubview(live2d)
        live2d.startRenderer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(assetRootPath: String, passiveIdle: Bool, onAspectRatioChange: @escaping (CGFloat) -> Void) {
        live2d.modelAspectRatioHandler = { aspectRatio in
            DispatchQueue.main.async {
                onAspectRatioChange(aspectRatio)
            }
        }

        if currentPassiveIdle != passiveIdle {
            currentPassiveIdle = passiveIdle
            live2d.passiveIdle = passiveIdle
        }

        guard currentAssetRootPath != assetRootPath else { return }
        currentAssetRootPath = assetRootPath
        live2d.assetRootPath = assetRootPath
        live2d.reloadModel()
    }

    override func layout() {
        super.layout()
        live2d.frame = bounds
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        live2d.frame = bounds
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        live2d.frame = bounds
    }

    override func mouseDown(with event: NSEvent) {
        onTap()
        super.mouseDown(with: event)
    }
}

@MainActor
final class AvatarPanelContentView: NSView {
    private let viewModel: CompanionViewModel
    private let onToggleChat: () -> Void
    private let live2d: CompanionLive2DView
    private var cancellables: Set<AnyCancellable> = []
    private var currentAssetRootPath: String

    init(viewModel: CompanionViewModel, onToggleChat: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onToggleChat = onToggleChat
        self.live2d = CompanionLive2DView(frame: .zero)
        self.currentAssetRootPath = viewModel.selectedModel.assetRootPath
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        live2d.translatesAutoresizingMaskIntoConstraints = false
        live2d.assetRootPath = currentAssetRootPath
        live2d.passiveIdle = viewModel.selectedModel.preset.passiveIdle
        live2d.emotionExpressionMap = viewModel.selectedModel.preset.emotionExpressions
        live2d.presenceState = viewModel.presenceState.rawValue
        live2d.emotionState = viewModel.emotionState.rawValue
        live2d.draggingActive = viewModel.isAvatarDragging
        live2d.manualEmotionPreview = viewModel.isManualPreviewMode
        live2d.tapHandler = { [weak self] in
            self?.onToggleChat()
        }
        live2d.scrollHandler = { [weak self] deltaY in
            DispatchQueue.main.async {
                self?.viewModel.adjustAvatarZoom(byScrollDelta: deltaY)
            }
        }
        live2d.modelAspectRatioHandler = { [weak self] aspectRatio in
            DispatchQueue.main.async {
                self?.viewModel.updateAvatarAspectRatio(aspectRatio)
            }
        }

        addSubview(live2d)

        NSLayoutConstraint.activate([
            live2d.leadingAnchor.constraint(equalTo: leadingAnchor),
            live2d.trailingAnchor.constraint(equalTo: trailingAnchor),
            live2d.topAnchor.constraint(equalTo: topAnchor),
            live2d.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        live2d.startRenderer()
        updateFromViewModel()
        bindViewModel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    private func bindViewModel() {
        viewModel.$selectedModelID
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateFromViewModel()
            }
            .store(in: &cancellables)

        viewModel.$presenceState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.live2d.presenceState = state.rawValue
            }
            .store(in: &cancellables)

        viewModel.$emotionState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.live2d.emotionState = state.rawValue
            }
            .store(in: &cancellables)

        viewModel.$manualEmotionOverride
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.live2d.manualEmotionPreview = self?.viewModel.isManualPreviewMode ?? false
            }
            .store(in: &cancellables)

        viewModel.$isManualPreviewMode
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.live2d.manualEmotionPreview = enabled
            }
            .store(in: &cancellables)

        viewModel.$isAvatarDragging
            .receive(on: RunLoop.main)
            .sink { [weak self] dragging in
                self?.live2d.draggingActive = dragging
            }
            .store(in: &cancellables)

        viewModel.$manualExpressionRequest
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] request in
                self?.live2d.triggerExpressionHints(request.hints)
            }
            .store(in: &cancellables)

        viewModel.$manualMotionRequest
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] request in
                self?.live2d.triggerMotionGroup(request.groupName)
            }
            .store(in: &cancellables)

    }

    private func updateFromViewModel() {
        let newAssetRootPath = viewModel.selectedModel.assetRootPath
        if currentAssetRootPath != newAssetRootPath {
            currentAssetRootPath = newAssetRootPath
            live2d.assetRootPath = newAssetRootPath
            live2d.passiveIdle = viewModel.selectedModel.preset.passiveIdle
            live2d.emotionExpressionMap = viewModel.selectedModel.preset.emotionExpressions
            live2d.reloadModel()
        } else {
            live2d.passiveIdle = viewModel.selectedModel.preset.passiveIdle
            live2d.emotionExpressionMap = viewModel.selectedModel.preset.emotionExpressions
        }
    }
}
