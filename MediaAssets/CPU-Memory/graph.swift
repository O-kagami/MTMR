import AppKit
import Darwin
import Foundation

struct Snapshot: Codable { var ticks: [UInt32]; var cpu: [Int]; var memory: [Int] }
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let command = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "sample"
let modeURL = root.appendingPathComponent("mode.txt")
let stateURL = root.appendingPathComponent("history.json")
let fd = open(root.appendingPathComponent("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
guard fd >= 0, flock(fd, LOCK_EX) == 0 else { print("--|cpu"); exit(1) }
defer { flock(fd, LOCK_UN); close(fd) }
func mode() -> String { (try? String(contentsOf: modeURL, encoding: .utf8)).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } == "memory" ? "memory" : "cpu" }
if command == "animate" {
    let oldMode = mode()
    let nextMode = oldMode == "cpu" ? "memory" : "cpu"
    let marker = root.appendingPathComponent("animating.txt")
    let output = root.appendingPathComponent("fade.png")
    guard let before = NSImage(contentsOf: root.appendingPathComponent(oldMode + "-graph.png")),
          let after = NSImage(contentsOf: root.appendingPathComponent(nextMode + "-graph.png")) else { exit(1) }
    defer { try? FileManager.default.removeItem(at: marker) }
    for frame in 0...6 {
        let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:96,pixelsHigh:96,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        rep.size = NSSize(width:24,height:24)
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep:rep)!
        context.shouldAntialias = true
        NSGraphicsContext.current = context
        let rect = NSRect(x:0,y:0,width:24,height:24)
        before.draw(in:rect,from:.zero,operation:.copy,fraction:1)
        after.draw(in:rect,from:.zero,operation:.sourceOver,fraction:CGFloat(frame)/6)
        NSGraphicsContext.restoreGraphicsState()
        guard let png=rep.representation(using:.png,properties:[:]) else { try? FileManager.default.removeItem(at: marker); exit(1) }
        do { try png.write(to:output,options:.atomic) } catch { try? FileManager.default.removeItem(at: marker); exit(1) }
        if frame == 0 {
            try "1".write(to:marker,atomically:true,encoding:.utf8)
            try (nextMode + "\n").write(to:modeURL,atomically:true,encoding:.utf8)
        }
        Thread.sleep(forTimeInterval:0.12)
    }
    try? FileManager.default.removeItem(at: marker)
    exit(0)
}
if command == "toggle" {
    let next = mode() == "cpu" ? "memory" : "cpu"
    try (next + "\n").write(to: modeURL, atomically: true, encoding: .utf8)
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("local.codex.mtmr.graph-mode-changed"), object:nil,
        userInfo:nil, deliverImmediately:true)
    print(next)
    exit(0)
}
if command != "sample" { exit(2) }
func ticks() -> [UInt32]? {
    var s = host_cpu_load_info(); var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
    let rc = withUnsafeMutablePointer(to: &s) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) } }
    guard rc == KERN_SUCCESS else { return nil }
    return [s.cpu_ticks.0,s.cpu_ticks.1,s.cpu_ticks.2,s.cpu_ticks.3]
}
func memory() -> Int? {
    var s = vm_statistics64(); var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let rc = withUnsafeMutablePointer(to: &s) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) } }
    var pageSize: vm_size_t = 0
    guard rc == KERN_SUCCESS, host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
    let total=ProcessInfo.processInfo.physicalMemory
    guard total > 0 else { return nil }
    let pages=UInt64(s.active_count)+UInt64(s.wire_count)+UInt64(s.compressor_page_count)
    return min(100,max(0,Int((Double(pages)*Double(pageSize)*100/Double(total)).rounded())))
}
func draw(_ values:[Int], _ type:String) throws {
    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:96,pixelsHigh:96,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    rep.size=NSSize(width:24,height:24)
    NSGraphicsContext.saveGraphicsState(); let context=NSGraphicsContext(bitmapImageRep:rep)!; context.shouldAntialias=true; NSGraphicsContext.current=context
    NSColor(calibratedRed:0.035,green:0.10,blue:0.10,alpha:1).setFill(); NSBezierPath(roundedRect:NSRect(x:0,y:0,width:24,height:24),xRadius:2,yRadius:2).fill()
    NSColor(calibratedRed:0.22,green:0.40,blue:0.38,alpha:0.5).setStroke()
    let grid=NSBezierPath(); grid.lineWidth=0.35
    for n in 1...3 { let p=CGFloat(n)*6;grid.move(to:NSPoint(x:0,y:p));grid.line(to:NSPoint(x:24,y:p));grid.move(to:NSPoint(x:p,y:0));grid.line(to:NSPoint(x:p,y:24)) };grid.stroke()
    if values.count > 1 {
        (type == "cpu" ? NSColor.systemGreen : NSColor.systemCyan).setStroke()
        let line=NSBezierPath();line.lineWidth=1.15;line.lineJoinStyle = .round;line.lineCapStyle = .round
        for (i,v) in values.enumerated() { let p=NSPoint(x: 1 + CGFloat(i)*22/CGFloat(max(1,values.count-1)),y:1 + CGFloat(min(100,max(0,v)))*22/100); if i==0 {line.move(to:p)} else {line.line(to:p)} }
        line.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let png=rep.representation(using:.png,properties:[:]) else { throw NSError(domain:"graph",code:1) }
    try png.write(to:root.appendingPathComponent(type+"-graph.png"),options:.atomic)
}
let previous=(try? Data(contentsOf:stateURL)).flatMap { try? JSONDecoder().decode(Snapshot.self,from:$0) }
let current=ticks()
var c=previous?.cpu ?? [], m=previous?.memory ?? []
if let current, let prev=previous?.ticks,prev.count==4 {
 let diff=zip(current,prev).map { UInt64($0 &- $1) };let total=diff.reduce(UInt64(0),+)
 if total > 0 { let idle=diff[Int(CPU_STATE_IDLE)]; c.append(min(100,max(0,Int((100*Double(total-idle)/Double(total)).rounded())))) }
}
if let v=memory() {m.append(v)}
c=Array(c.suffix(24));m=Array(m.suffix(24))
if let current,let d=try? JSONEncoder().encode(Snapshot(ticks:current,cpu:c,memory:m)) {try? d.write(to:stateURL,options:.atomic)}
try? draw(c,"cpu");try? draw(m,"memory")
let active=mode();let latest=(active=="cpu" ? c.last : m.last)
print("\(latest.map { "\($0)%" } ?? "--")|\(active)")
