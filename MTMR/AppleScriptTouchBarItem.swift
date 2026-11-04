import Foundation

class AppleScriptTouchBarItem: CustomButtonTouchBarItem {
    private let interval: TimeInterval
    private var forceHideConstraint: NSLayoutConstraint!
    private let alternativeImages: [String: SourceProtocol]
    private let session: WorkerSession?
    private var lastIconKey: String?
    private var lastIconStamp: String?
    private var modeObserver: NSObjectProtocol?
    private var pendingRefresh: DispatchWorkItem?
    private var refreshing = false
    private var refreshRequested = false
    var playbackAnimationEnabled = false {
        didSet { if playbackAnimationEnabled { view.wantsLayer = true } }
    }

    @objc override func handleGestureSingleTap() {
        if playbackAnimationEnabled { TouchBarMotion.pulse(view) }
        super.handleGestureSingleTap()
    }

    init?(identifier: NSTouchBarItem.Identifier, source: SourceProtocol, interval: TimeInterval, alternativeImages: [String: SourceProtocol]) {
        self.interval = max(0.05, interval)
        self.alternativeImages = alternativeImages
        self.session = makeWorkerSession(source: source)
        super.init(identifier: identifier, title: "⏳")
        forceHideConstraint = view.widthAnchor.constraint(equalToConstant: 0)
        isBordered = false
        if alternativeImages["cpu"] != nil && alternativeImages["memory"] != nil {
            modeObserver = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("local.codex.mtmr.graph-mode-changed"), object: nil, queue: .main
            ) { [weak self] _ in self?.refreshImmediately() }
        }
        if session == nil { title = "no script" }
        else { refreshAndSchedule() }
    }

    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        pendingRefresh?.cancel()
        if let observer = modeObserver { DistributedNotificationCenter.default().removeObserver(observer) }
        session?.stop()
    }

    private func refreshImmediately() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        if refreshing { refreshRequested = true; return }
        refreshAndSchedule()
    }

    private func refreshAndSchedule() {
        guard let session = session else { return }
        if refreshing { refreshRequested = true; return }
        refreshing = true
        // Any run may require a new Automation permission dialog.
        session.run(timeout: 30) { [weak self] result in
            guard let self = self else { return }
            let delay: TimeInterval
            switch result {
            case .text(let value):
                self.update(title: value, icon: nil)
                delay = self.interval
            case .list(let values):
                self.update(title: values.first ?? "", icon: values.count > 1 ? values[1] : nil)
                delay = self.interval
            case .error(let reason) where reason == "automation denied":
                self.update(title: "権限", icon: nil)
                self.refreshing = false
                self.refreshRequested = false
                return // the user may grant permission and restart; do not reprompt
            case .error, .timeout, .busy, .stopped, .cooldown:
                delay = max(1, self.interval) // keep last good display and avoid a tight retry loop
            }
            self.refreshing = false
            if self.refreshRequested {
                self.refreshRequested = false
                self.refreshAndSchedule()
            } else {
                let next = DispatchWorkItem { [weak self] in self?.refreshAndSchedule() }
                self.pendingRefresh = next
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: next)
            }
        }
    }

    private func update(title: String, icon: String?) {
        if self.title != title { self.title = title }
        if forceHideConstraint.isActive != title.isEmpty { forceHideConstraint.isActive = title.isEmpty }
        if let icon = icon, let source = alternativeImages[icon] {
            let stamp = iconStamp(source)
            // Files such as Spotify artwork may be replaced at the same path.
            if icon != lastIconKey || stamp != lastIconStamp {
                if let decoded = source.image {
                    // Only a real CPU ↔ memory mode change gets a transition;
                    // fresh chart samples under the same key must not animate.
                    if TouchBarMotion.isGraphModeChange(previous: lastIconKey, next: icon,
                                                        available: Set(alternativeImages.keys)) {
                        view.wantsLayer = true
                        TouchBarMotion.slideDown(view, key: "cpuMemoryMode")
                    }
                    if TouchBarMotion.shouldFadePlayback(enabled: playbackAnimationEnabled, previous: lastIconKey, next: icon) {
                        TouchBarMotion.fade(view, key: "playbackState", duration: 0.12)
                    }
                    image = decoded
                    lastIconKey = icon
                    lastIconStamp = stamp
                } else {
                    image = nil
                    lastIconKey = nil
                    lastIconStamp = nil
                }
            }
        }
    }

    private func iconStamp(_ source: SourceProtocol) -> String {
        guard let config = source as? Source, let path = config.filePath else { return "inline" }
        let expanded = (path as NSString).expandingTildeInPath
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: expanded) else { return "missing" }
        let inode = (attrs[.systemFileNumber] as? NSNumber)?.stringValue ?? "?"
        let size = (attrs[.size] as? NSNumber)?.stringValue ?? "?"
        let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(inode):\(size):\(modified)"
    }
}

extension DispatchQueue {
    static let appleScriptQueue = DispatchQueue(label: "mtmr.applescript")
}
