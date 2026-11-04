import Foundation
var gate = LevelReadGate(settleDelay: 0.6)
let initial = gate.generation
precondition(gate.allows(initial, issuedAt: 1, completedAt: 1))
gate.interacted(at: 10)
precondition(!gate.allows(initial, issuedAt: 9, completedAt: 11), "read from before drag must be dropped")
let during = gate.generation
precondition(!gate.allows(during, issuedAt: 10.1, completedAt: 10.2), "read during drag cooldown must be dropped")
gate.interacted(at: 10.3)
precondition(!gate.allows(during, issuedAt: 10.2, completedAt: 11.2), "later drag invalidates earlier read")
let last = gate.generation
precondition(!gate.allows(last, issuedAt: 10.7, completedAt: 10.8))
precondition(gate.allows(last, issuedAt: 11, completedAt: 11.1), "fresh settled read should be accepted")
precondition(!gate.allows(last, issuedAt: 10.4, completedAt: 20), "a stale read completing after the settle delay must be rejected")
precondition(!gate.allows(last, issuedAt: 11, completedAt: 10.9), "non-monotonic read timing rejected")
gate.invalidate()
precondition(!gate.allows(last, issuedAt: 19, completedAt: 20), "mode change invalidates in-flight reads")
precondition(!gate.allows(gate.generation, issuedAt: .nan, completedAt: 20), "invalid timestamps rejected")
print("LevelReadGate tests passed")
var writes: [Float] = []
let success: (Float) -> Bool = { writes.append($0); return true }
precondition(LevelWritePolicy.apply(80, write: success, readActual: { 33 }) == .accepted(80))
precondition(writes == [80])
let fail: (Float) -> Bool = { writes.append($0); return false }
precondition(LevelWritePolicy.apply(25, write: fail, readActual: { 33 }) == .reverted(33), "failed write displays actual level")
precondition(LevelWritePolicy.apply(25, write: fail, readActual: { nil }) == .unavailable, "failed write and unavailable reading display unknown")
let previousCount = writes.count
precondition(LevelWritePolicy.apply(.nan, write: success, readActual: { 12 }) == .reverted(12), "invalid request reverts")
precondition(writes.count == previousCount, "invalid request cannot reach device")
precondition(LevelWritePolicy.apply(200, write: success, readActual: { .nan }) == .unavailable, "invalid actual value cannot be displayed")
print("LevelWritePolicy tests passed")
