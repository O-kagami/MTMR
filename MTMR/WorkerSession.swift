import Foundation
import Darwin

/// Prototype only: every instance owns one persistent child and at most one call.
final class WorkerSession {
    enum Source { case inline(String); case file(String) }
    enum Reply: Equatable {
        case text(String), list([String]), error(String), timeout, busy, stopped, cooldown
    }
    private let queue = DispatchQueue(label: "mtmr.worker.session.\(UUID().uuidString)")
    private let callbackQueue: DispatchQueue
    private let executable: String
    private var source: Source
    private var process: Process?
    private var inputChannel: DispatchIO?
    private var output: FileHandle?
    private var generation = 0
    private var sequence = 0
    private var expectedID: Int?
    private var phase = "idle"
    private var buffer = Data()
    private var callback: ((Reply) -> Void)?
    private var timer: DispatchSourceTimer?
    private var failures = 0
    private var retryAfter: TimeInterval = 0
    private let maxResponseBytes = 1_000_000

    init(executable: String, source: Source, callbackQueue: DispatchQueue = .main) {
        self.executable = executable; self.source = source; self.callbackQueue = callbackQueue
    }

    func run(timeout: TimeInterval, completion: @escaping (Reply) -> Void) {
        queue.async { [self] in
            guard callback == nil else { callbackQueue.async { completion(.busy) }; return }
            guard timeout.isFinite && timeout > 0 else { callbackQueue.async { completion(.timeout) }; return }
            guard ProcessInfo.processInfo.systemUptime >= retryAfter else { callbackQueue.async { completion(.cooldown) }; return }
            callback = completion
            let clock = DispatchSource.makeTimerSource(queue: queue)
            timer = clock
            clock.schedule(deadline: .now() + timeout)
            clock.setEventHandler { [weak self] in self?.finish(.timeout, reset: true) }
            clock.resume()
            if process == nil { launch() } else { sendRun() }
        }
    }

    /// Replacement is explicit, for source updates. It resets persistent properties.
    func replaceSource(_ newSource: Source, completion: @escaping () -> Void) {
        queue.async { [self] in
            if callback != nil { finish(.stopped, reset: true) } else { teardown() }
            source = newSource
            failures = 0; retryAfter = 0
            callbackQueue.async(execute: completion)
        }
    }

    func stop(completion: @escaping () -> Void = {}) {
        queue.async { [self] in
            if callback != nil { finish(.stopped, reset: true) } else { teardown() }
            callbackQueue.async(execute: completion)
        }
    }

    private func launch() {
        generation += 1
        let thisGeneration = generation
        let proc = Process(), inputPipe = Pipe(), outputPipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.standardInput = inputPipe; proc.standardOutput = outputPipe
        proc.standardError = FileHandle.nullDevice
        proc.terminationHandler = { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self = self, self.generation == thisGeneration, self.process != nil else { return }
                self.finish(.error("worker exited"), reset: true)
            }
        }
        do { try proc.run() } catch { finish(.error("worker launch failed"), reset: true); return }
        process = proc
        let duplicated = Darwin.dup(inputPipe.fileHandleForWriting.fileDescriptor)
        try? inputPipe.fileHandleForWriting.close()
        guard duplicated >= 0 else { finish(.error("worker pipe setup failed"), reset: true); return }
        inputChannel = DispatchIO(type: .stream, fileDescriptor: duplicated, queue: queue) { _ in Darwin.close(duplicated) }
        output = outputPipe.fileHandleForReading
        buffer.removeAll(keepingCapacity: false)
        output?.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            self?.queue.async { [weak self] in self?.receive(bytes, generation: thisGeneration) }
        }
        phase = "initializing"
        var request: [String: Any] = ["op": "init"]
        switch source { case .inline(let text): request["source"] = text; case .file(let path): request["path"] = path }
        send(request)
    }

    private func sendRun() { phase = "executing"; send(["op": "run"]) }
    private func send(_ payload: [String: Any]) {
        sequence += 1; expectedID = sequence
        var msg = payload; msg["id"] = sequence
        guard let bytes = try? JSONSerialization.data(withJSONObject: msg), let channel = inputChannel else {
            finish(.error("request encoding failed"), reset: true); return
        }
        let packet = bytes + Data([10])
        let dispatchBytes = packet.withUnsafeBytes { DispatchData(bytes: $0) }
        let requestGeneration = generation
        channel.write(offset: 0, data: dispatchBytes, queue: queue) { [weak self] done, _, error in
            guard done, error != 0, let self = self,
                  self.generation == requestGeneration, self.callback != nil else { return }
            self.finish(.error("worker pipe failed"), reset: true)
        }
    }
    private func receive(_ bytes: Data, generation eventGeneration: Int) {
        guard generation == eventGeneration, process != nil else { return }
        guard !bytes.isEmpty else { finish(.error("worker closed output"), reset: true); return }
        buffer.append(bytes)
        guard buffer.count <= maxResponseBytes else { finish(.error("worker response too large"), reset: true); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            guard let response = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let id = response["id"] as? Int, id == expectedID,
                  let kind = response["kind"] as? String else { finish(.error("invalid worker response"), reset: true); return }
            if phase == "initializing" && kind == "ready" { sendRun(); continue }
            guard phase == "executing" else { finish(.error("worker initialization failed"), reset: true); return }
            if kind == "text", let value = response["value"] as? String { finish(.text(value), reset: false) }
            else if kind == "list", let values = response["values"] as? [String] { finish(.list(values), reset: false) }
            else if kind == "error" {
                let reason = response["reason"] as? String ?? "script failed"
                if reason == "automation denied" {
                    finish(.error(reason), reset: true)
                    retryAfter = .infinity // avoid repeated permission prompts until restart
                } else { finish(.error("script failed"), reset: false) }
            }
            else { finish(.error("invalid worker response"), reset: true) }
        }
    }
    private func finish(_ result: Reply, reset: Bool) {
        timer?.cancel(); timer = nil
        switch result {
        case .timeout, .error:
            failures = min(failures + 1, 7)
            retryAfter = ProcessInfo.processInfo.systemUptime + min(60, pow(2, Double(failures - 1)))
        case .text, .list: failures = 0; retryAfter = 0
        default: break
        }
        let completion = callback; callback = nil; expectedID = nil; phase = "idle"
        if reset { teardown() }
        if let completion = completion { callbackQueue.async { completion(result) } }
    }
    deinit {
        timer?.cancel()
        teardown()
    }

    private func teardown() {
        generation += 1
        output?.readabilityHandler = nil
        inputChannel?.close(flags: .stop); inputChannel = nil
        try? output?.close()
        output = nil
        let old = process; process = nil
        if let old = old, old.isRunning {
            old.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                if old.isRunning { Darwin.kill(old.processIdentifier, SIGKILL) }
            }
        }
        buffer.removeAll(keepingCapacity: false)
    }
}

func makeWorkerSession(source: SourceProtocol) -> WorkerSession? {
    let spec: WorkerSession.Source
    if let config = source as? Source, let path = config.filePath { spec = .file(path) }
    else if let text = source.string { spec = .inline(text) }
    else { return nil }
    let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/MTMRScriptWorker").path
    return WorkerSession(executable: executable, source: spec)
}

/// Keep tap actions ordered without creating unlimited processes while a script stalls.
final class ScriptActionRunner {
    private let session: WorkerSession
    private var pending = 0
    private var running = false
    init(session: WorkerSession) { self.session = session }
    deinit { session.stop() }
    func invoke() {
        if !Thread.isMainThread { DispatchQueue.main.async { [weak self] in self?.invoke() }; return }
        pending = min(pending + 1, 4)
        drain()
    }
    private func drain() {
        guard !running, pending > 0 else { return }
        pending -= 1
        running = true
        session.run(timeout: 30) { [weak self] result in
            guard let self = self else { return }
            self.running = false
            switch result {
            case .text, .list:
                self.drain()
            default: self.pending = 0
            }
        }
    }
}

func makeScriptAction(source: SourceProtocol) -> (() -> Void)? {
    guard let session = makeWorkerSession(source: source) else { return nil }
    let runner = ScriptActionRunner(session: session)
    return { runner.invoke() }
}

func makeInlineScriptAction(_ text: String) -> (() -> Void) {
    let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/MTMRScriptWorker").path
    let runner = ScriptActionRunner(session: WorkerSession(executable: executable, source: .inline(text)))
    return { runner.invoke() }
}
