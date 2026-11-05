import Foundation
import Darwin

/// Runs one bounded helper request at a time. A timed-out or cancelled request
/// disables the session: it may already have changed system state, so the UI
/// must not claim failure or retry. No private API runs on the UI thread.
protocol TouchBarRequesting {
    func request(_ arguments: [String], completion: @escaping (IsolatedTouchBarClient.Result) -> Void)
    func stop()
}

final class IsolatedTouchBarClient: TouchBarRequesting {
    enum Result {
        case success(Data)
        case failed(Int32)
        case busy
        case unavailable
        case indeterminate
    }
    private struct Request {
        let id: UInt64
        let task: Process
        let completion: (Result) -> Void
    }
    private let queue = DispatchQueue(label: "mtmr.touchbar.brightness.helper")
    private let helper: URL
    private let timeout: TimeInterval
    private var active: Request?
    private var counter: UInt64 = 0
    private var poisoned = false

    init(helper: URL, timeout: TimeInterval = 2) { self.helper = helper; self.timeout = timeout }
    func request(_ arguments: [String], completion: @escaping (Result) -> Void) {
        queue.async { [self] in
            guard !self.poisoned else { self.deliver(.indeterminate, to: completion); return }
            guard self.active == nil else { self.deliver(.busy, to: completion); return }
            let pipe = Pipe(), task = Process()
            task.executableURL = self.helper
            task.arguments = arguments
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            self.counter &+= 1
            let id = self.counter
            task.terminationHandler = { [weak self] result in
                guard let self = self else { return }
                self.queue.async {
                    guard let current = self.active, current.id == id else { return }
                    self.active = nil
                    guard !self.poisoned else { return }
                    let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
                    self.deliver(result.terminationStatus == 0 ? .success(bytes) : .failed(result.terminationStatus), to: current.completion)
                }
            }
            do {
                try task.run()
                self.active = Request(id: id, task: task, completion: completion)
            } catch {
                self.deliver(.unavailable, to: completion)
                return
            }
            self.queue.asyncAfter(deadline: .now() + self.timeout) {
                guard let current = self.active, current.id == id else { return }
                self.poisoned = true
                self.terminate(current.task, id: id)
                self.deliver(.indeterminate, to: current.completion)
            }
        }
    }
    /// On explicit Auto, quit or cancellation, abandon any active request.
    /// The system may already have accepted a write; no rollback is attempted.
    func stop() {
        queue.async {
            guard !self.poisoned else { return }
            self.poisoned = true
            guard let current = self.active else { return }
            self.terminate(current.task, id: current.id)
            self.deliver(.indeterminate, to: current.completion)
        }
    }
    private func terminate(_ task: Process, id: UInt64) {
        if task.isRunning { task.terminate() }
        // The task remains uniquely tracked until its termination handler runs.
        // Escalate if SIGTERM did not stop the child. This cannot retract a
        // request already accepted by the OS; the result stays indeterminate.
        queue.asyncAfter(deadline: .now() + 0.25) {
            guard self.active?.id == id, task.isRunning else { return }
            _ = kill(task.processIdentifier, SIGKILL)
        }
    }
    private func deliver(_ result: Result, to callback: @escaping (Result) -> Void) {
        DispatchQueue.main.async { callback(result) }
    }
}
