import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Darwin

// Keep the original pixel dimensions; encode a separate image with an alpha mask.
func roundedArtwork(_ data: Data) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0, width <= 4096, height <= 4096,
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    let radius = CGFloat(min(width, height)) * 0.12
    context.clear(rect)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    context.draw(image, in: rect)
    guard let masked = context.makeImage() else { return nil }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, masked, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return output as Data
}

// Transient MTMR-owned helper. No login item, no persistent service.
// Startup: `artwork-fast <directory> <initial spotify:track:id>`.
final class ArtworkWorker: NSObject, URLSessionTaskDelegate {
    let directory: URL
    let output: URL
    let placeholder: Data
    var currentID = ""
    var generation = UUID()
    var task: URLSessionDataTask?
    var cache: [String: Data] = [:]
    var observer: NSObjectProtocol?
    var session: URLSession!
    var foregroundTimer: Timer?
    var terminationObserver: NSObjectProtocol?
    let selfTest: Bool
    var started = Date()

    init(directory: URL, selfTest: Bool) throws {
        self.directory = directory
        output = directory.appendingPathComponent("artwork.png")
        placeholder = try Data(contentsOf: directory.appendingPathComponent("artwork-placeholder.png"))
        self.selfTest = selfTest
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 6
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func start(initial: String) {
        let name = selfTest ? "local.codex.mtmr.artwork-test" : "com.spotify.client.PlaybackStateChanged"
        observer = DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            let state = note.userInfo?["Player State"] as? String ?? "Stopped"
            let id = note.userInfo?["Track ID"] as? String ?? ""
            self.update(state == "Playing" || state == "Paused" ? id : "")
        }
        if !selfTest {
            terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object:nil, queue:.main) { [weak self] n in
                if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.bundleIdentifier == "com.spotify.client" { self?.update("") }
            }
            foregroundTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                let bundles = CommandLine.arguments.contains("--lifecycle-test") ? ["local.codex.mtmr.nonexistent-test"] : ["Toxblh.MTMR", "local.codex.MTMRLocalTest"]
                if bundles.allSatisfy({ NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }) { exit(0) }
            }
        }
        update(initial)
    }

    func validID(_ raw: String) -> String? {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "spotify", parts[1] == "track", parts[2].count == 22,
              parts[2].utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else { return nil }
        return String(parts[2])
    }
    func write(_ data: Data) { try? data.write(to: output, options: .atomic) }
    func update(_ raw: String) {
        let id = validID(raw) ?? ""
        if id == currentID && !id.isEmpty { return }
        generation = UUID(); let token = generation
        task?.cancel(); task = nil
        currentID = id
        write(placeholder)
        guard !id.isEmpty else { return }
        if let data = cache[id] { write(data); return }
        var components = URLComponents(string:"https://open.spotify.com/oembed")!
        components.queryItems = [URLQueryItem(name:"url",value:"https://open.spotify.com/track/\(id)")]
        task = session.dataTask(with: components.url!) { [weak self] data, response, error in
            guard let self else { return }
            let imageURL: URL? = {
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let data, data.count < 256_000,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String:Any],
                      let raw = json["thumbnail_url"] as? String, let url = URL(string: raw),
                      url.scheme == "https", let host = url.host,
                      host.hasSuffix(".scdn.co") || host.hasSuffix(".spotifycdn.com") else { return nil }
                return url
            }()
            DispatchQueue.main.async {
                guard self.generation == token else { return }
                guard let imageURL else { self.retry(id:id,token:token); return }
                self.download(imageURL, id: id, token: token)
            }
        }
        task?.resume()
    }
    func retry(id: String, token: UUID) {
        currentID = ""
        DispatchQueue.main.asyncAfter(deadline:.now()+5) { [weak self] in
            guard let self, self.generation == token, self.currentID.isEmpty else { return }
            self.update("spotify:track:" + id)
        }
    }
    func download(_ url: URL, id: String, token: UUID) {
        task = session.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      http.mimeType?.hasPrefix("image/") == true,
                      let data, data.count <= 5_000_000, let rounded = roundedArtwork(data) else { self.retry(id:id,token:token); return }
                if self.cache.count >= 24 { self.cache.removeAll() }
                self.cache[id] = rounded
                self.write(rounded)
                if self.selfTest { print(String(format:"download and update %.3fs", Date().timeIntervalSince(self.started))); fflush(stdout); exit(0) }
            }
        }
        task?.resume()
    }
}

let args = CommandLine.arguments
if args.count == 4 && args[1] == "--round-test" {
    guard let input = try? Data(contentsOf: URL(fileURLWithPath: args[2])),
          let result = roundedArtwork(input) else { exit(1) }
    do { try result.write(to: URL(fileURLWithPath: args[3]), options: .atomic); exit(0) }
    catch { exit(1) }
}
if args.count < 3 { exit(2) }
let directory = URL(fileURLWithPath: args[1], isDirectory:true)
let isTest = args.contains("--self-test")
let isStatus = args.contains("--status")
// `flock` is scoped to the lifetime of this process. A dead helper releases it automatically.
var lockFD:Int32 = -1
if !isTest {
    lockFD = open(directory.appendingPathComponent("artwork-fast.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard lockFD >= 0 else { exit(2) }
    let acquired = flock(lockFD, LOCK_EX | LOCK_NB) == 0
    if isStatus { exit(acquired ? 1 : 0) }
    if !acquired { exit(0) }
}
do {
    let worker = try ArtworkWorker(directory:directory,selfTest:isTest)
    worker.start(initial: isTest ? "" : args[2])
    if isTest {
        DispatchQueue.main.asyncAfter(deadline:.now()+0.1) {
            worker.started = Date()
            DistributedNotificationCenter.default().postNotificationName(Notification.Name("local.codex.mtmr.artwork-test"), object:nil, userInfo:["Player State":"Playing", "Track ID":args[2]], deliverImmediately:true)
        }
    }
    if isTest { DispatchQueue.main.asyncAfter(deadline:.now()+15) { fputs("test timed out\n",stderr); exit(1) } }
    withExtendedLifetime(worker) { RunLoop.main.run() }
} catch { fputs("artwork helper could not start\n",stderr); exit(1) }
