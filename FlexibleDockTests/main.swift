import AppKit
let app = NSApplication.shared
func layout(total: CGFloat, right: CGFloat, center: CGFloat = 0) -> [CGFloat] {
    let leading = NSView(), dock = NSScrollView(), middle = NSView(), trailing = NSView()
    let views: [NSView] = center == 0 ? [leading, dock, trailing] : [leading, dock, middle, trailing]
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: total, height: 30))
    parent.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
        stack.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
        stack.topAnchor.constraint(equalTo: parent.topAnchor),
        stack.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        leading.widthAnchor.constraint(equalToConstant: 246),
        trailing.widthAnchor.constraint(equalToConstant: right)
    ])
    if center > 0 { middle.widthAnchor.constraint(equalToConstant: center).isActive = true }
    FlexibleDockLayout.configure(dock)
    parent.layoutSubtreeIfNeeded()
    return [leading.frame.width, dock.frame.width, trailing.frame.width, middle.frame.width]
}
let a = layout(total: 1000, right: 240)
let b = layout(total: 1000, right: 284)
assert(a[0] == 246 && a[2] == 240 && a[1] == 498)
assert(b[0] == 246 && b[2] == 284 && b[1] == 454)
assert(a[1] - b[1] == 44)
let c = layout(total: 900, right: 240, center: 100)
assert(c[0] == 246 && c[1] == 290 && c[2] == 240 && c[3] == 100)
print("FlexibleDockLayout tests passed")
