import AppKit
import Combine
import SwiftUI

@MainActor
final class CompanionWindowCoordinator: NSObject, NSWindowDelegate {
    private let viewModel: CompanionViewModel
    private var avatarPanel: CompanionPanel?
    private var bubblePanel: CompanionPanel?
    private var cancellables: Set<AnyCancellable> = []

    init(viewModel: CompanionViewModel) {
        self.viewModel = viewModel
        super.init()
        bindViewModel()
    }

    func show() {
        let avatar = makeAvatarPanel()
        avatarPanel = avatar
        avatar.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func bringCompanionToMouseScreen() {
        guard let avatarPanel else { return }

        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? avatarPanel.screen ?? NSScreen.main
        let visibleFrame = targetScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? avatarPanel.frame
        let panelSize = viewModel.avatarLayout.panelSize
        let newFrame = NSRect(
            x: visibleFrame.maxX - panelSize.width - 20,
            y: visibleFrame.minY,
            width: panelSize.width,
            height: panelSize.height
        )
        avatarPanel.setFrame(newFrame, display: true, animate: true)
        avatarPanel.orderFrontRegardless()
        avatarPanel.makeKeyAndOrderFront(nil)

        if bubblePanel?.isVisible == true {
            positionBubble(relativeTo: newFrame)
            bubblePanel?.orderFrontRegardless()
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func toggleBubble() {
        guard let avatarPanel else { return }
        if bubblePanel?.isVisible == true {
            bubblePanel?.orderOut(nil)
            viewModel.isBubbleVisible = false
        } else {
            let bubble = bubblePanel ?? makeBubblePanel()
            bubblePanel = bubble
            positionBubble(relativeTo: avatarPanel.frame)
            bubble.orderFront(nil)
            bubble.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            viewModel.isBubbleVisible = true
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == avatarPanel else { return }
        viewModel.pulseDragging()
        if bubblePanel?.isVisible == true {
            positionBubble(relativeTo: window.frame)
        }
    }

    private func makeAvatarPanel() -> CompanionPanel {
        let panelSize = viewModel.avatarLayout.panelSize
        let panel = CompanionPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelSize.width, height: panelSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        configure(panel: panel)
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.contentView = AvatarPanelContentView(viewModel: viewModel) { [weak self] in
            self?.toggleBubble()
        }
        panel.setFrame(initialAvatarFrame(), display: true)
        return panel
    }

    private func makeBubblePanel() -> CompanionPanel {
        let panel = CompanionPanel(
            contentRect: NSRect(x: 0, y: 0, width: 396, height: 354),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        configure(panel: panel)
        panel.contentView = NSHostingView(rootView: BubblePanelView(viewModel: viewModel))
        return panel
    }

    private func configure(panel: CompanionPanel) {
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.hidesOnDeactivate = false
    }

    private func initialAvatarFrame() -> NSRect {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = viewModel.avatarLayout.panelSize
        return NSRect(
            x: visible.maxX - size.width - 28,
            y: visible.minY + 24,
            width: size.width,
            height: size.height
        )
    }

    private func positionBubble(relativeTo avatarFrame: NSRect) {
        guard let bubblePanel else { return }
        let size = bubblePanel.frame.size
        let x = avatarFrame.minX - size.width + 86
        let y = avatarFrame.minY + 34
        bubblePanel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func bindViewModel() {
        Publishers.CombineLatest(viewModel.$avatarAspectRatio, viewModel.$avatarZoom)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateAvatarPanelSize()
            }
            .store(in: &cancellables)
    }

    private func updateAvatarPanelSize() {
        guard let avatarPanel else { return }
        let newSize = viewModel.avatarLayout.panelSize
        let currentFrame = avatarPanel.frame
        guard abs(currentFrame.width - newSize.width) > 0.5 || abs(currentFrame.height - newSize.height) > 0.5 else {
            return
        }

        let newFrame = NSRect(
            x: currentFrame.maxX - newSize.width,
            y: currentFrame.minY,
            width: newSize.width,
            height: newSize.height
        )
        avatarPanel.setFrame(newFrame, display: true, animate: true)
        avatarPanel.contentView?.frame = NSRect(origin: .zero, size: newSize)
        avatarPanel.contentView?.needsLayout = true

        if bubblePanel?.isVisible == true {
            positionBubble(relativeTo: newFrame)
        }
    }
}

final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
