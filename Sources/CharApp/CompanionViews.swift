import AppKit
import Combine
import Live2DBridge
import RealityKit
import SwiftUI
import VRMRealityKit

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

            avatarView
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

    @ViewBuilder
    private var avatarView: some View {
        switch viewModel.selectedModel.runtime {
        case .live2d:
            Live2DAvatarRepresentable(
                assetRootPath: viewModel.selectedModel.assetRootPath,
                passiveIdle: viewModel.selectedModel.preset.passiveIdle,
                onTap: onToggleChat
            ) { aspectRatio in
                viewModel.updateAvatarAspectRatio(aspectRatio)
            }
        case .vrm:
            VRMAvatarRepresentable(
                filePath: viewModel.selectedModel.entryPath,
                presenceState: viewModel.presenceState,
                onTap: onToggleChat
            ) { aspectRatio in
                viewModel.updateAvatarAspectRatio(aspectRatio)
            }
        case .vroidProject:
            UnsupportedAvatarView(
                title: viewModel.selectedModel.displayName,
                detail: "Это файл проекта VRoid Studio. Экспортируй его как .vrm, и я смогу встроить его как полноценный аватар."
            )
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

struct VRMAvatarRepresentable: NSViewRepresentable {
    let filePath: String
    let presenceState: CompanionPresenceState
    let onTap: () -> Void
    let onAspectRatioChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> CompanionVRMRealityView {
        let view = CompanionVRMRealityView(frame: .zero)
        view.filePath = filePath
        view.tapHandler = onTap
        view.scrollHandler = { deltaY in
            context.coordinator.onScroll(deltaY)
        }
        view.aspectRatioHandler = onAspectRatioChange
        view.presenceState = presenceState
        view.reloadModel()
        return view
    }

    func updateNSView(_ nsView: CompanionVRMRealityView, context: Context) {
        nsView.tapHandler = onTap
        nsView.scrollHandler = { deltaY in
            context.coordinator.onScroll(deltaY)
        }
        nsView.aspectRatioHandler = onAspectRatioChange
        nsView.presenceState = presenceState
        if nsView.filePath != filePath {
            nsView.filePath = filePath
            nsView.reloadModel()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var onScroll: (CGFloat) -> Void = { _ in }
    }
}

@available(macOS 15.0, *)
@MainActor
final class CompanionVRMRealityView: ARView {
    var filePath: String = ""
    var presenceState: CompanionPresenceState = .idle
    var speechLevel: CGFloat = 0
    var draggingActive: Bool = false
    var tapHandler: (() -> Void)?
    var scrollHandler: ((CGFloat) -> Void)?
    var aspectRatioHandler: ((CGFloat) -> Void)?

    private var mouseDownPoint: NSPoint = .zero
    private var draggedSinceMouseDown = false
    private let rootAnchor = AnchorEntity(world: .zero)
    private let cameraAnchor = AnchorEntity(world: .zero)
    private let cameraEntity = PerspectiveCamera()
    private var vrmEntity: VRMEntity?
    private var vrmaPlayer: VRMAPlayer?
    private var posePlayer: VRoidPosePlayer?
    private var updateSubscription: Cancellable?

    // MARK: - Animation Event Mappings (set from ViewModel via binding)
    var animationEventMappings: [String: [AnimationSlotItem]] = CompanionProfile.defaultEventMappings()

    // MARK: - Idle animation cycling
    private var idleWaitTime: TimeInterval = 0
    private var idleNextTrigger: TimeInterval = 0.5
    private var idleConverting = false
    private var idleLastItemId: UUID? = nil   // avoid repeating the same clip
    private var wasInIdleState = false
    private var startupGreetingPlayed = false  // play startup greeting once on model load
    private var idleCyclingActive = false      // true while a VRMA/BVH idle chain is running

    // MARK: - Pose hold timer (auto-clear event-triggered poses after N seconds)
    private var poseHoldTimer: Timer?
    private let poseHoldDuration: TimeInterval = 4.0

    func applyEventPose(filePath: String) {
        applyPose(filePath: filePath)
        poseHoldTimer?.invalidate()
        poseHoldTimer = Timer.scheduledTimer(withTimeInterval: poseHoldDuration,
                                              repeats: false) { [weak self] _ in
            self?.clearPose()
        }
    }
    private var orbitTarget = SIMD3<Float>(0, 0.8, 0)
    private var orbitDistance: Float = 1.45
    private var blinkTimer: Timer?
    private var activeExpression: CompanionVRMExpressionPreset = .neutral
    private var primaryExpressionTargets: [BlendShapeKey: CGFloat] = [:]
    private var primaryExpressionCurrent: [BlendShapeKey: CGFloat] = [:]
    private var blinkKeys: [BlendShapeKey] = [
        .preset(.blink),
        .preset(.blinkL),
        .preset(.blinkR),
        .custom("Blink"),
        .custom("blink"),
        .custom("Closed"),
        .custom("closed"),
    ]
    private var blinkTarget: CGFloat = 0
    private var blinkCurrent: CGFloat = 0
    private var mouthTime: TimeInterval = 0
    private var mouthCurrent: CGFloat = 0
    private var mouthKeys: [BlendShapeKey] = [
        .preset(.a),
        .custom("A"),
        .custom("a"),
        .custom("Aa"),
        .custom("aa"),
    ]
    private var motionTime: TimeInterval = 0
    private var headEntity: Entity?
    private var neckEntity: Entity?
    private var chestEntity: Entity?
    private var spineEntity: Entity?
    private var headBaseRotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var neckBaseRotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var chestBaseRotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var spineBaseRotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var rootBasePosition = SIMD3<Float>(repeating: 0)
    private var rootBaseRotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var vrmConvention: VRMCoordinateConvention = .v0
    private var boneRestTransforms: [Humanoid.Bones: Transform] = [:]
    private var glTFChestEntity: Entity?
    private var glTFChestRestTransform: Transform?
    private var lookYawCurrent: Float = 0
    private var lookPitchCurrent: Float = 0
    private var dragYawCurrent: Float = 0
    private var dragRollCurrent: Float = 0
    private var dragPitchCurrent: Float = 0
    private var dragYawTarget: Float = 0
    private var dragRollTarget: Float = 0
    private var dragPitchTarget: Float = 0

    // Smooth look-at blend-in after a non-look-at animation ends
    private var lookAtWeight: Float = 1.0
    private let lookAtBlendDuration: Float = 0.4
    private var lookAtFromNeckRot: simd_quatf? = nil
    private var lookAtFromHeadRot: simd_quatf? = nil
    private var prevVrmaPlayerActive = false
    private var prevVrmaSkipLookBones = false
    private var prevPosePlayerActive = false

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        environment.background = .color(.clear)

        scene.addAnchor(rootAnchor)
        scene.addAnchor(cameraAnchor)
        cameraAnchor.addChild(cameraEntity)
        updateCameraTransform()
        scheduleNextBlink()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func layout() {
        super.layout()
        if let entity = vrmEntity?.entity {
            updateOrbitTarget(for: entity)
        }
    }

    func reloadModel() {
        guard !filePath.isEmpty else { return }

        do {
            if let vrmEntity {
                vrmEntity.entity.removeFromParent()
                self.vrmEntity = nil
            }
            vrmaPlayer = nil
            startupGreetingPlayed = false
            wasInIdleState = false
            idleWaitTime = 0
            idleConverting = false
            idleCyclingActive = false
            updateSubscription?.cancel()
            updateSubscription = nil

            let loader = try VRMEntityLoader(withURL: URL(fileURLWithPath: filePath))
            let vrmEntity = try loader.loadEntity()
            switch vrmEntity.vrm {
            case .v0: vrmConvention = .v0
            case .v1: vrmConvention = .v1
            }
            applyDefaultPoseTransform(to: vrmEntity)
            rootAnchor.addChild(vrmEntity.entity)
            self.vrmEntity = vrmEntity
            captureRigReferences(for: vrmEntity)

            normalizeScale(for: vrmEntity.entity)
            updateOrbitTarget(for: vrmEntity.entity)
            applyExpression(.neutral)

            updateSubscription = scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                Task { @MainActor in
                    guard let self, let vrmEntity = self.vrmEntity else { return }
                    vrmEntity.update(at: event.deltaTime)
                    self.updateExpressionAnimation(deltaTime: event.deltaTime)
                    self.updateMouthAnimation(deltaTime: event.deltaTime)
                    self.updateBodyAnimation(deltaTime: event.deltaTime)
                    if let player = self.vrmaPlayer {
                        let stillPlaying = player.update(deltaTime: event.deltaTime)
                        if !stillPlaying {
                            self.vrmaPlayer = nil
                        }
                    }
                    self.posePlayer?.update(deltaTime: event.deltaTime)
                    self.updateIdleAnimation(deltaTime: event.deltaTime)
                }
            }
        } catch {
            aspectRatioHandler?(0.62)
            Swift.print("Failed to load VRM at \(filePath): \(String(reflecting: error))")
        }
    }

    func playVRMA(filePath: String) {
        guard let vrmEntity else { return }
        posePlayer = nil
        do {
            vrmaPlayer = try VRMAPlayer(
                filePath: filePath,
                vrmEntity: vrmEntity,
                restTransforms: boneRestTransforms,
                chestEntity: glTFChestEntity,
                chestRestTransform: glTFChestRestTransform,
                convention: vrmConvention
            )
        } catch {
            Swift.print("Failed to play VRMA at \(filePath): \(String(reflecting: error))")
            vrmaPlayer = nil
        }
    }

    // MARK: - Idle animation cycling

    private func updateIdleAnimation(deltaTime: TimeInterval) {
        let isIdle = presenceState == .idle

        // Reset when we (re-)enter idle state mid-session
        if isIdle && !wasInIdleState {
            idleWaitTime = 0
            idleNextTrigger = TimeInterval.random(in: 5...10)
            idleCyclingActive = false
        }
        wasInIdleState = isIdle

        // Only tick when idle and nothing else is playing or loading
        guard isIdle, vrmaPlayer == nil, posePlayer == nil, !idleConverting else { return }

        // On model load, play greeting2 first — this eliminates the startup T-pose
        if !startupGreetingPlayed {
            startupGreetingPlayed = true
            idleWaitTime = 0
            idleNextTrigger = 0.5   // after greeting ends, fire first idle after 0.5s
            playStartupGreeting()
            return  // vrmaPlayer is now set; guard will block ticking until it finishes
        }

        // If a cycling chain is active, chain the next animation immediately — no pause
        if idleCyclingActive {
            playNextIdleAnimation()
            return
        }

        // First animation in a new session — wait for the initial trigger delay
        idleWaitTime += deltaTime
        guard idleWaitTime >= idleNextTrigger else { return }

        idleWaitTime = 0
        idleNextTrigger = TimeInterval.random(in: 8...18)
        playNextIdleAnimation()
    }

    private func playStartupGreeting() {
        let items = animationEventMappings[AnimationEventType.startup.rawValue] ?? []
        guard let item = items.randomElement() else { return }
        guard presenceState == .idle, vrmaPlayer == nil, posePlayer == nil else { return }
        let fullPath = AppEnvironment.assetsRootURL.appendingPathComponent(item.filePath).path
        switch item.assetType {
        case .vrma:
            playVRMA(filePath: fullPath)
            vrmaPlayer?.skipLookBones = false
        case .bvh:
            idleConverting = true
            Task.detached(priority: .utility) { [weak self, fullPath, item] in
                do {
                    let vrmaPath = try BVHConverter.vrmaPath(for: fullPath)
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.idleConverting = false
                        guard self.presenceState == .idle,
                              self.vrmaPlayer == nil, self.posePlayer == nil else { return }
                        self.playVRMA(filePath: vrmaPath)
                        self.vrmaPlayer?.skipLookBones = false
                    }
                } catch {
                    await MainActor.run { [weak self] in self?.idleConverting = false }
                }
            }
        case .pose:
            applyEventPose(filePath: fullPath)
        }
    }

    private func playNextIdleAnimation() {
        let items = animationEventMappings[AnimationEventType.idle.rawValue] ?? []
        guard !items.isEmpty else { return }
        let available = items.filter { $0.id != idleLastItemId }
        let item = (available.isEmpty ? items : available).randomElement()!
        idleLastItemId = item.id

        let fullPath = AppEnvironment.assetsRootURL.appendingPathComponent(item.filePath).path

        switch item.assetType {
        case .vrma:
            guard presenceState == .idle, vrmaPlayer == nil, posePlayer == nil else { return }
            playVRMA(filePath: fullPath)
            vrmaPlayer?.skipLookBones = true
            idleCyclingActive = true   // chain: when this ends, play next immediately

        case .bvh:
            idleConverting = true
            idleCyclingActive = true   // will continue chaining after conversion
            Task.detached(priority: .utility) { [weak self, fullPath] in
                do {
                    let vrmaPath = try BVHConverter.vrmaPath(for: fullPath)
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.idleConverting = false
                        guard self.presenceState == .idle,
                              self.vrmaPlayer == nil,
                              self.posePlayer == nil else { return }
                        self.playVRMA(filePath: vrmaPath)
                        self.vrmaPlayer?.skipLookBones = true
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.idleConverting = false
                        self?.idleCyclingActive = false  // conversion failed — stop chain
                    }
                }
            }

        case .pose:
            guard presenceState == .idle, vrmaPlayer == nil else { return }
            idleCyclingActive = false   // pose is held, not chained; poseHoldTimer clears it
            applyEventPose(filePath: fullPath)
        }
    }

    func applyPose(filePath: String) {
        guard let vrmEntity else { return }
        vrmaPlayer = nil
        do {
            posePlayer = try VRoidPosePlayer(
                filePath: filePath,
                vrmEntity: vrmEntity,
                restTransforms: boneRestTransforms,
                chestEntity: glTFChestEntity,
                chestRestTransform: glTFChestRestTransform,
                convention: vrmConvention
            )
        } catch {
            Swift.print("Failed to apply pose at \(filePath): \(String(reflecting: error))")
            posePlayer = nil
        }
    }

    func clearPose() {
        posePlayer = nil
    }

    func applyExpression(_ expression: CompanionVRMExpressionPreset) {
        activeExpression = expression
        var nextTargets: [BlendShapeKey: CGFloat] = [:]
        for key in primaryExpressionKeys {
            nextTargets[key] = 0
        }
        for key in expressionCandidates(for: expression) {
            nextTargets[key] = 1
        }
        primaryExpressionTargets = nextTargets
    }

    func applyEmotionPreview(_ emotion: CompanionEmotionState?) {
        let expression: CompanionVRMExpressionPreset
        switch emotion {
        case .happy, .excited:
            expression = .happy
        case .angry:
            expression = .angry
        case .shy, .thinking:
            expression = .smiling
        case .sleepy:
            expression = .sad
        case .none, .neutral:
            expression = .neutral
        }
        applyExpression(expression)
    }

    private func applyDefaultPoseTransform(to vrmEntity: VRMEntity) {
        vrmEntity.entity.position = .zero
        switch vrmEntity.vrm {
        case .v0:
            vrmEntity.entity.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        case .v1:
            vrmEntity.entity.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        }
    }

    private func captureRigReferences(for vrmEntity: VRMEntity) {
        headEntity = vrmEntity.humanoid.node(for: .head)
        neckEntity = vrmEntity.humanoid.node(for: .neck)
        chestEntity = vrmEntity.humanoid.node(for: .upperChest)
        spineEntity = vrmEntity.humanoid.node(for: .spine)

        headBaseRotation = headEntity?.transform.rotation ?? simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        neckBaseRotation = neckEntity?.transform.rotation ?? simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        chestBaseRotation = chestEntity?.transform.rotation ?? simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        spineBaseRotation = spineEntity?.transform.rotation ?? simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        rootBasePosition = vrmEntity.entity.transform.translation
        rootBaseRotation = vrmEntity.entity.transform.rotation

        lookYawCurrent = 0
        lookPitchCurrent = 0
        dragYawCurrent = 0
        dragRollCurrent = 0
        dragPitchCurrent = 0
        dragYawTarget = 0
        dragRollTarget = 0
        dragPitchTarget = 0
        lookAtWeight = 1.0
        lookAtFromNeckRot = nil
        lookAtFromHeadRot = nil
        prevVrmaPlayerActive = false
        prevVrmaSkipLookBones = false

        captureBoneRestTransforms(for: vrmEntity)
    }

    private static let allTrackedBones: [Humanoid.Bones] = [
        .hips, .spine, .upperChest, .neck, .head, .jaw, .leftEye, .rightEye,
        .leftShoulder, .rightShoulder,
        .leftUpperArm, .rightUpperArm, .leftLowerArm, .rightLowerArm,
        .leftHand, .rightHand,
        .leftUpperLeg, .rightUpperLeg, .leftLowerLeg, .rightLowerLeg,
        .leftFoot, .rightFoot, .leftToes, .rightToes,
        .leftThumbProximal, .leftThumbIntermediate, .leftThumbDistal,
        .leftIndexProximal, .leftIndexIntermediate, .leftIndexDistal,
        .leftMiddleProximal, .leftMiddleIntermediate, .leftMiddleDistal,
        .leftRingProximal, .leftRingIntermediate, .leftRingDistal,
        .leftLittleProximal, .leftLittleIntermediate, .leftLittleDistal,
        .rightThumbProximal, .rightThumbIntermediate, .rightThumbDistal,
        .rightIndexProximal, .rightIndexIntermediate, .rightIndexDistal,
        .rightMiddleProximal, .rightMiddleIntermediate, .rightMiddleDistal,
        .rightRingProximal, .rightRingIntermediate, .rightRingDistal,
        .rightLittleProximal, .rightLittleIntermediate, .rightLittleDistal,
    ]

    private func captureBoneRestTransforms(for vrmEntity: VRMEntity) {
        boneRestTransforms.removeAll()
        for bone in Self.allTrackedBones {
            if let entity = vrmEntity.humanoid.node(for: bone) {
                boneRestTransforms[bone] = entity.transform
            }
        }

        glTFChestEntity = nil
        glTFChestRestTransform = nil
        if let spineNode = vrmEntity.humanoid.node(for: .spine),
           let upperChestNode = vrmEntity.humanoid.node(for: .upperChest) {
            for child in spineNode.children {
                if child === upperChestNode {
                    break
                }
                if isAncestorOf(target: upperChestNode, in: child) {
                    glTFChestEntity = child
                    glTFChestRestTransform = child.transform
                    break
                }
            }
        }
    }

    private func isAncestorOf(target: Entity, in entity: Entity) -> Bool {
        if entity === target { return true }
        for child in entity.children {
            if isAncestorOf(target: target, in: child) { return true }
        }
        return false
    }

    private func normalizeScale(for entity: Entity) {
        let bounds = entity.visualBounds(relativeTo: nil)
        let height = bounds.max.y - bounds.min.y
        guard height > 0.001 else { return }
        let targetHeight: Float = 2.0
        let scale = targetHeight / height
        entity.transform.scale = SIMD3<Float>(repeating: scale)
    }

    private func updateOrbitTarget(for entity: Entity) {
        let bounds = entity.visualBounds(relativeTo: nil)
        let center = (bounds.min + bounds.max) * 0.5
        let extents = bounds.max - bounds.min
        orbitTarget = center

        let viewportAspect = max(Float(self.bounds.width / max(self.bounds.height, 1)), 0.1)
        let verticalFOV: Float = .pi / 3
        let horizontalFOV = 2 * atan(tan(verticalFOV / 2) * viewportAspect)
        let fitHeightDistance = (extents.y * 0.5) / tan(verticalFOV / 2)
        let fitWidthDistance = (extents.x * 0.5) / tan(horizontalFOV / 2)
        let depthPadding = max(extents.z * 0.25, 0.02)
        orbitDistance = max(fitHeightDistance, fitWidthDistance) + depthPadding
        updateCameraTransform()

        let height = CGFloat(extents.y)
        let width = CGFloat(extents.x)
        guard height > 0.001 else {
            aspectRatioHandler?(0.62)
            return
        }
        let ratio = max(min(width / height, 1.4), 0.5)
        aspectRatioHandler?(ratio)
    }

    private func updateCameraTransform() {
        let cameraLift: Float = orbitDistance * 0.22
        let adjustedTarget = orbitTarget + SIMD3<Float>(0, cameraLift * 0.28, 0)
        let position = adjustedTarget + SIMD3<Float>(0, cameraLift * 0.72, orbitDistance)
        cameraEntity.look(at: adjustedTarget, from: position, relativeTo: nil)
    }

    private func scheduleNextBlink() {
        blinkTimer?.invalidate()
        let interval = TimeInterval.random(in: 2.4...5.2)
        blinkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.performBlink()
                self.scheduleNextBlink()
            }
        }
    }

    private func performBlink() {
        guard vrmEntity != nil else { return }
        blinkTarget = 1.0

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) { [weak self] in
            guard let self else { return }
            self.blinkTarget = 0.0
        }
    }

    private var primaryExpressionKeys: [BlendShapeKey] {
        [
            .preset(.neutral),
            .preset(.joy),
            .preset(.angry),
            .preset(.sorrow),
            .preset(.fun),
            .custom("Neutral"),
            .custom("neutral"),
            .custom("Smiling"),
            .custom("Smile"),
            .custom("smile"),
            .custom("Sad"),
            .custom("sad"),
            .custom("Angry"),
            .custom("angry"),
            .custom("Happy"),
            .custom("happy"),
            .custom("Joy"),
            .custom("joy"),
            .custom("Surprised"),
            .custom("surprised"),
            .custom("Surprise"),
            .custom("surprise"),
        ]
    }

    private func expressionCandidates(for expression: CompanionVRMExpressionPreset) -> [BlendShapeKey] {
        switch expression {
        case .neutral:
            return [.preset(.neutral), .custom("Neutral"), .custom("neutral")]
        case .smiling:
            return [.preset(.fun), .custom("Smiling"), .custom("Smile"), .custom("smile"), .custom("Relaxed")]
        case .sad:
            return [.preset(.sorrow), .custom("Sad"), .custom("sad")]
        case .angry:
            return [.preset(.angry), .custom("Angry"), .custom("angry")]
        case .happy:
            return [.preset(.joy), .custom("Happy"), .custom("happy"), .custom("Joy"), .custom("joy")]
        case .surprised:
            return [.custom("Surprised"), .custom("surprised"), .custom("Surprise"), .custom("surprise"), .custom("Open Wide")]
        }
    }

    private func setBlendShape(_ value: CGFloat, for key: BlendShapeKey) {
        vrmEntity?.setBlendShape(value: value, for: key)
    }

    private func blendShapeValue(for key: BlendShapeKey) -> CGFloat {
        vrmEntity?.blendShape(for: key) ?? 0
    }

    private func updateExpressionAnimation(deltaTime: TimeInterval) {
        let smoothing = CGFloat(1 - exp(-8.5 * deltaTime))

        for key in primaryExpressionKeys {
            let current = primaryExpressionCurrent[key] ?? blendShapeValue(for: key)
            let target = primaryExpressionTargets[key] ?? 0
            let next = current + (target - current) * smoothing
            primaryExpressionCurrent[key] = next
            setBlendShape(next, for: key)
        }

        let effectiveBlinkTarget: CGFloat = blinkTarget * blinkIntensity(for: activeExpression)
        let blinkNext = blinkCurrent + (effectiveBlinkTarget - blinkCurrent) * CGFloat(1 - exp(-22.0 * deltaTime))
        blinkCurrent = blinkNext
        for key in blinkKeys {
            setBlendShape(blinkNext, for: key)
        }
    }

    private func updateMouthAnimation(deltaTime: TimeInterval) {
        mouthTime += deltaTime

        let target: CGFloat
        switch presenceState {
        case .speaking:
            if speechLevel > 0.01 {
                target = min(max(speechLevel * 1.25, 0.06), 0.95)
            } else {
                let base = 0.14 + 0.42 * max(0, sin(mouthTime * 10.5))
                let accent = 0.14 * max(0, sin(mouthTime * 23.0 + 0.8))
                target = min(base + accent, 0.78)
            }
        case .thinking, .listening, .idle:
            target = 0
        }

        let smoothing = CGFloat(1 - exp(-14.0 * deltaTime))
        mouthCurrent += (target - mouthCurrent) * smoothing

        for key in mouthKeys {
            setBlendShape(mouthCurrent, for: key)
        }
    }

    private func updateBodyAnimation(deltaTime: TimeInterval) {
        guard let vrmEntity else { return }

        // Detect when a non-look-at animation or pose ends so we can blend look-at back in smoothly.
        let hadVrma = prevVrmaPlayerActive
        let hadSkipLook = prevVrmaSkipLookBones
        let hadPose = prevPosePlayerActive
        prevVrmaPlayerActive = vrmaPlayer != nil
        prevVrmaSkipLookBones = vrmaPlayer?.skipLookBones ?? false
        prevPosePlayerActive = posePlayer != nil

        if hadVrma && !hadSkipLook && vrmaPlayer == nil {
            // Animation just ended and it was controlling neck/head — capture its final pose.
            lookAtFromNeckRot = neckEntity?.transform.rotation
            lookAtFromHeadRot = headEntity?.transform.rotation
            lookAtWeight = 0
        } else if hadPose && posePlayer == nil && vrmaPlayer == nil {
            // Pose just ended — capture head/neck position for smooth look-at blend-in.
            lookAtFromNeckRot = neckEntity?.transform.rotation
            lookAtFromHeadRot = headEntity?.transform.rotation
            lookAtWeight = 0
        }
        // Advance blend weight each frame.
        if lookAtWeight < 1 {
            lookAtWeight = min(1, lookAtWeight + Float(deltaTime) / lookAtBlendDuration)
        }

        if vrmaPlayer != nil || posePlayer != nil {
            // Always keep root entity at base (VRMAPlayer doesn't touch it).
            vrmEntity.entity.transform.translation = rootBasePosition
            vrmEntity.entity.transform.rotation = rootBaseRotation

            // For idle animations the neck/head are intentionally left to look-at
            // (VRMAPlayer.skipLookBones = true), so we fall through to apply it.
            // For poses, look-at also keeps tracking neck/head so there is no freeze
            // while the pose holds — the pose player only overrides bones in the pose file,
            // and head/neck are usually absent from body-only poses (arms-crossed, etc.).
            let skipLook = vrmaPlayer?.skipLookBones ?? false
            let isIdleAnim = (presenceState == .idle && skipLook) || (posePlayer != nil)
            if !isIdleAnim {
                spineEntity?.transform.rotation = spineBaseRotation
                chestEntity?.transform.rotation = chestBaseRotation
                neckEntity?.transform.rotation = neckBaseRotation
                headEntity?.transform.rotation = headBaseRotation
                if let glTFChestEntity, let glTFChestRestTransform {
                    glTFChestEntity.transform = glTFChestRestTransform
                }
                return
            }
            // Fall through to apply look-at to neck/head only.
        }
        motionTime += deltaTime

        let localMouse = currentNormalizedMousePosition()
        let clampedX = max(-1.0, min(1.0, localMouse.x))
        let clampedY = max(-1.0, min(1.0, localMouse.y))

        let lookStateScale: Float
        switch presenceState {
        case .thinking:
            lookStateScale = 0.35
        case .listening:
            lookStateScale = 0.95
        case .speaking:
            lookStateScale = 0.78
        case .idle:
            lookStateScale = 0.65
        }

        let lookYawTarget = clampedX * 0.22 * lookStateScale
        let lookPitchTarget = -clampedY * 0.12 * lookStateScale
        let lookSmoothing = Float(1 - exp(-Double(7.5) * deltaTime))
        lookYawCurrent += (lookYawTarget - lookYawCurrent) * lookSmoothing
        lookPitchCurrent += (lookPitchTarget - lookPitchCurrent) * lookSmoothing

        if !draggingActive {
            dragYawTarget = 0
            dragRollTarget = 0
            dragPitchTarget = 0
        }
        let dragSmoothing = Float(1 - exp(-Double(9.0) * deltaTime))
        dragYawCurrent += (dragYawTarget - dragYawCurrent) * dragSmoothing
        dragRollCurrent += (dragRollTarget - dragRollCurrent) * dragSmoothing
        dragPitchCurrent += (dragPitchTarget - dragPitchCurrent) * dragSmoothing

        let thinkingTilt: Float = presenceState == .thinking ? -0.12 : 0
        let isIdleAnim = vrmaPlayer?.skipLookBones == true

        // Root entity: skip if idle animation already set it above, otherwise set it now.
        if !isIdleAnim {
            vrmEntity.entity.transform.translation = rootBasePosition
            vrmEntity.entity.transform.rotation =
                rootBaseRotation
                * simd_quatf(angle: dragYawCurrent, axis: SIMD3<Float>(0, 1, 0))
                * simd_quatf(angle: dragPitchCurrent, axis: SIMD3<Float>(1, 0, 0))
                * simd_quatf(angle: dragRollCurrent, axis: SIMD3<Float>(0, 0, 1))
        }

        if let neckEntity {
            let neckTarget =
                neckBaseRotation
                * simd_quatf(angle: lookYawCurrent * 0.45, axis: SIMD3<Float>(0, 1, 0))
                * simd_quatf(angle: lookPitchCurrent * 0.55 + thinkingTilt * 0.35, axis: SIMD3<Float>(1, 0, 0))
            if let fromRot = lookAtFromNeckRot, lookAtWeight < 1 {
                neckEntity.transform.rotation = simd_slerp(fromRot, neckTarget, lookAtWeight)
            } else {
                neckEntity.transform.rotation = neckTarget
            }
        }

        if let headEntity {
            let headTarget =
                headBaseRotation
                * simd_quatf(angle: lookYawCurrent, axis: SIMD3<Float>(0, 1, 0))
                * simd_quatf(angle: lookPitchCurrent + thinkingTilt, axis: SIMD3<Float>(1, 0, 0))
                * simd_quatf(angle: dragRollCurrent * 0.25, axis: SIMD3<Float>(0, 0, 1))
            if let fromRot = lookAtFromHeadRot, lookAtWeight < 1 {
                headEntity.transform.rotation = simd_slerp(fromRot, headTarget, lookAtWeight)
            } else {
                headEntity.transform.rotation = headTarget
            }
        }
    }

    private func currentNormalizedMousePosition() -> SIMD2<Float> {
        guard let window else { return .zero }
        let global = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: global)
        let localPoint = convert(windowPoint, from: nil)
        guard bounds.width > 1, bounds.height > 1 else { return .zero }

        let normalizedX = Float(((localPoint.x / bounds.width) - 0.5) * 2.0)
        let normalizedY = Float(((localPoint.y / bounds.height) - 0.5) * 2.0)
        return SIMD2<Float>(normalizedX, normalizedY)
    }

    private func blinkIntensity(for expression: CompanionVRMExpressionPreset) -> CGFloat {
        switch expression {
        case .happy:
            return 0.22
        case .neutral, .smiling, .sad, .angry, .surprised:
            return 1.0
        }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        draggedSinceMouseDown = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - mouseDownPoint.x
        let dy = point.y - mouseDownPoint.y
        if (dx * dx + dy * dy) > 25 {
            draggedSinceMouseDown = true
        }
        let clampedDX = max(-80.0, min(80.0, dx))
        let clampedDY = max(-80.0, min(80.0, dy))
        dragYawTarget = Float(clampedDX / 80.0) * 0.22
        dragRollTarget = Float(clampedDX / 80.0) * -0.16
        dragPitchTarget = Float(clampedDY / 80.0) * -0.10
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        dragYawTarget = 0
        dragRollTarget = 0
        dragPitchTarget = 0
        if !draggedSinceMouseDown {
            tapHandler?()
        }
        super.mouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        scrollHandler?(event.scrollingDeltaY)
    }
}

struct UnsupportedAvatarView: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.rectangle.stack.fill")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(.black.opacity(0.72))

            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.82))

            Text(detail)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.black.opacity(0.68))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.white.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(.black.opacity(0.16), lineWidth: 1.2)
                )
        )
    }
}

@MainActor
final class AvatarPanelContentView: NSView {
    private let viewModel: CompanionViewModel
    private let onToggleChat: () -> Void
    private var live2d: CompanionLive2DView?
    private var vrmView: CompanionVRMRealityView?
    private var placeholderView: NSHostingView<UnsupportedAvatarView>?
    private var cancellables: Set<AnyCancellable> = []
    private var currentModelIdentity: String
    private var currentRuntime: CompanionAvatarRuntime

    init(viewModel: CompanionViewModel, onToggleChat: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onToggleChat = onToggleChat
        self.currentModelIdentity = viewModel.selectedModel.id
        self.currentRuntime = viewModel.selectedModel.runtime
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        installAvatarView(for: viewModel.selectedModel)
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
                self?.live2d?.presenceState = state.rawValue
                self?.vrmView?.presenceState = state
            }
            .store(in: &cancellables)

        viewModel.speech.$speechLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] level in
                self?.vrmView?.speechLevel = level
            }
            .store(in: &cancellables)

        viewModel.$emotionState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.live2d?.emotionState = state.rawValue
            }
            .store(in: &cancellables)

        viewModel.$manualEmotionOverride
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.live2d?.manualEmotionPreview = self?.viewModel.isManualPreviewMode ?? false
                self?.vrmView?.applyEmotionPreview(self?.viewModel.manualEmotionOverride)
            }
            .store(in: &cancellables)

        viewModel.$isManualPreviewMode
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.live2d?.manualEmotionPreview = enabled
            }
            .store(in: &cancellables)

        viewModel.$isAvatarDragging
            .receive(on: RunLoop.main)
            .sink { [weak self] dragging in
                self?.live2d?.draggingActive = dragging
                self?.vrmView?.draggingActive = dragging
            }
            .store(in: &cancellables)

        viewModel.$manualExpressionRequest
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] request in
                self?.live2d?.triggerExpressionHints(request.hints)
            }
            .store(in: &cancellables)

        viewModel.$manualMotionRequest
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] request in
                self?.live2d?.triggerMotionGroup(request.groupName)
            }
            .store(in: &cancellables)

        viewModel.$manualVRMARequest
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] request in
                self?.vrmView?.playVRMA(filePath: request.filePath)
            }
            .store(in: &cancellables)

        viewModel.$manualPoseRequest
            .receive(on: RunLoop.main)
            .sink { [weak self] request in
                if let request {
                    self?.vrmView?.applyPose(filePath: request.filePath)
                } else {
                    self?.vrmView?.clearPose()
                }
            }
            .store(in: &cancellables)

        viewModel.$manualVRMExpressionRequest
            .receive(on: RunLoop.main)
            .sink { [weak self] request in
                guard let self, let vrmView = self.vrmView else { return }
                if let request {
                    vrmView.applyExpression(request.expression)
                } else {
                    vrmView.applyExpression(.neutral)
                }
            }
            .store(in: &cancellables)

        viewModel.$profile
            .map { $0.animationEventMappings }
            .removeDuplicates { lhs, rhs in
                // Compare by serialisation to avoid unnecessary reloads
                (try? JSONEncoder().encode(lhs)) == (try? JSONEncoder().encode(rhs))
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] mappings in
                self?.vrmView?.animationEventMappings = mappings
            }
            .store(in: &cancellables)

    }

    private func installAvatarView(for model: CompanionModelOption) {
        subviews.forEach { $0.removeFromSuperview() }
        live2d = nil
        vrmView = nil
        placeholderView = nil

        switch model.runtime {
        case .live2d:
            let live2d = CompanionLive2DView(frame: .zero)
            live2d.translatesAutoresizingMaskIntoConstraints = false
            live2d.assetRootPath = model.assetRootPath
            live2d.passiveIdle = model.preset.passiveIdle
            live2d.emotionExpressionMap = model.preset.emotionExpressions
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
            addPinnedSubview(live2d)
            live2d.startRenderer()
            self.live2d = live2d

        case .vrm:
            let vrmView = CompanionVRMRealityView(frame: .zero)
            vrmView.translatesAutoresizingMaskIntoConstraints = false
            vrmView.filePath = model.entryPath
            vrmView.tapHandler = { [weak self] in
                self?.onToggleChat()
                self?.viewModel.triggerEventAnimation(.tap)
            }
            vrmView.scrollHandler = { [weak self] deltaY in
                DispatchQueue.main.async {
                    self?.viewModel.adjustAvatarZoom(byScrollDelta: deltaY)
                }
            }
            vrmView.aspectRatioHandler = { [weak self] aspectRatio in
                DispatchQueue.main.async {
                    self?.viewModel.updateAvatarAspectRatio(aspectRatio)
                }
            }
            vrmView.presenceState = viewModel.presenceState
            vrmView.speechLevel = viewModel.speech.speechLevel
            vrmView.draggingActive = viewModel.isAvatarDragging
            vrmView.animationEventMappings = viewModel.profile.animationEventMappings
            addPinnedSubview(vrmView)
            vrmView.reloadModel()
            self.vrmView = vrmView

        case .vroidProject:
            let placeholder = NSHostingView(
                rootView: UnsupportedAvatarView(
                    title: model.displayName,
                    detail: "Это проект VRoid Studio. Экспортируй его как .vrm, и я смогу использовать его как полноценный 3D-аватар."
                )
            )
            placeholder.translatesAutoresizingMaskIntoConstraints = false
            addPinnedSubview(placeholder)
            viewModel.updateAvatarAspectRatio(0.62)
            self.placeholderView = placeholder
        }
    }

    private func addPinnedSubview(_ subview: NSView) {
        addSubview(subview)
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: trailingAnchor),
            subview.topAnchor.constraint(equalTo: topAnchor),
            subview.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func updateFromViewModel() {
        let selectedModel = viewModel.selectedModel
        let newModelIdentity = selectedModel.id
        let runtimeChanged = currentRuntime != selectedModel.runtime

        if runtimeChanged || currentModelIdentity != newModelIdentity {
            currentRuntime = selectedModel.runtime
            currentModelIdentity = newModelIdentity
            installAvatarView(for: selectedModel)
        }

        if let live2d {
            live2d.passiveIdle = selectedModel.preset.passiveIdle
            live2d.emotionExpressionMap = selectedModel.preset.emotionExpressions
        }
    }
}
