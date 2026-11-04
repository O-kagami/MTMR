import Foundation

class AppleScriptTouchBarItem: CustomButtonTouchBarItem {
    private let interval: TimeInterval
    private var forceHideConstraint: NSLayoutConstraint!
    private let alternativeImages: [String: SourceProtocol]
    private let session: WorkerSession?
    private var lastIconKey: String?
    private var lastIconStamp: String?

    init?(identifier: NSTouchBarItem.Identifier, source: SourceProtocol, interval: TimeInterval, alternativeImages: [String: SourceProtocol]) {
        self.interval = max(0.05, interval)
        self.alternativeImages = alternativeImages
        self.session = makeWorkerSession(source: source)
        super.init(identifier: identifier, title: "⏳")
        forceHideConstraint = view.widthAnchor.constraint(equalToConstant: 0)
        isBordered = false
        if session == nil { title = "no script" }
        else { refreshAndSchedule() }
    }

    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { session?.stop() }

    private func refreshAndSchedule() {
        guard let session = session else { return }
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
                return // the user may grant permission and restart; do not reprompt
            case .error, .timeout, .busy, .stopped, .cooldown:
                delay = max(1, self.interval) // keep last good display and avoid a tight retry loop
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refreshAndSchedule() }
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
