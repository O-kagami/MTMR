import Foundation
import Darwin

/// Retain the returned source for the lifetime of a one-shot helper. There is
/// still no guarantee that a request already accepted by the OS is reversible.
func watchParent(_ owner: pid_t) -> DispatchSourceProcess? {
    guard owner > 1, getppid() == owner else { return nil }
    let source = DispatchSource.makeProcessSource(identifier: owner, eventMask: .exit,
                                                   queue: DispatchQueue.global(qos: .utility))
    source.setEventHandler { _exit(75) }
    source.resume()
    guard getppid() == owner else { source.cancel(); return nil }
    return source
}
