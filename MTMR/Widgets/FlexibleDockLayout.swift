import AppKit

/// Gives the selected Dock the available horizontal space in its parent stack.
enum FlexibleDockLayout {
    static func configure(_ view: NSView) {
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.widthAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true
    }
}
