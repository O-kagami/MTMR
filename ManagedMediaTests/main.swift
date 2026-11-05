import Foundation
let fm = FileManager.default
let contents = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory:true)
let testRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory:true)
try? fm.removeItem(at:testRoot)
try fm.createDirectory(at:testRoot.appendingPathComponent("MTMR"),withIntermediateDirectories:true)
let existingPreset=testRoot.appendingPathComponent("MTMR/items.json")
try "existing preset".write(to:existingPreset,atomically:true,encoding:.utf8)
let resources=contents.appendingPathComponent("Resources",isDirectory:true)
let helpers=contents.appendingPathComponent("Helpers",isDirectory:true)
let dest=try ManagedMediaInstaller.install(resources:resources,helpers:helpers,support:testRoot,ownerID:"org.example.Test")
let existing=try String(contentsOf:existingPreset,encoding:.utf8)
precondition(existing == "existing preset")
let mode=dest.appendingPathComponent("CPU-Memory/mode.txt")
let initial=try String(contentsOf:mode,encoding:.utf8)
precondition(initial == "cpu\n")
let graph=dest.appendingPathComponent("CPU-Memory/graph")
precondition(fm.isExecutableFile(atPath:graph.path))
let sample=Process(); sample.executableURL=graph; sample.arguments=[dest.appendingPathComponent("CPU-Memory").path,"sample"]
let pipe=Pipe();sample.standardOutput=pipe;try sample.run();sample.waitUntilExit();precondition(sample.terminationStatus==0)
precondition(fm.fileExists(atPath:dest.appendingPathComponent("CPU-Memory/cpu-graph.png").path))
precondition(fm.fileExists(atPath:dest.appendingPathComponent("CPU-Memory/memory-graph.png").path))
let history=dest.appendingPathComponent("CPU-Memory/history.json")
try "memory\n".write(to:mode,atomically:true,encoding:.utf8)
try "custom-history".write(to:history,atomically:true,encoding:.utf8)
let savedIcon=dest.appendingPathComponent("CPU-Memory/cpu.png")
try "custom-icon".write(to:savedIcon,atomically:true,encoding:.utf8)
let savedArtwork=dest.appendingPathComponent("SpotifyArtwork/artwork.png")
try "custom-artwork".write(to:savedArtwork,atomically:true,encoding:.utf8)
let savedPrevious=dest.appendingPathComponent("SpotifyArtwork/previous.png")
try "custom-previous".write(to:savedPrevious,atomically:true,encoding:.utf8)
let savedNextScript=dest.appendingPathComponent("SpotifyArtwork/next.applescript")
try "custom-next".write(to:savedNextScript,atomically:true,encoding:.utf8)
_ = try ManagedMediaInstaller.install(resources:resources,helpers:helpers,support:testRoot,ownerID:"org.example.Test")
let modeAgain=try String(contentsOf:mode,encoding:.utf8)
let historyAgain=try String(contentsOf:history,encoding:.utf8)
let artworkAgain=try String(contentsOf:savedArtwork,encoding:.utf8)
let iconAgain=try String(contentsOf:savedIcon,encoding:.utf8)
precondition(modeAgain == "memory\n" && historyAgain == "custom-history" && artworkAgain == "custom-artwork" && iconAgain == "custom-icon")
let previousAgain=try String(contentsOf:savedPrevious,encoding:.utf8)
let nextAgain=try String(contentsOf:savedNextScript,encoding:.utf8)
precondition(previousAgain == "custom-previous" && nextAgain == "custom-next")
let data=try Data(contentsOf:resources.appendingPathComponent("defaultPreset.json"))
let json=try JSONSerialization.jsonObject(with:data) as! [[String:Any]]
precondition(json.contains { $0["type"] as? String == "localLevel" })
precondition(json.contains { $0["flexibleDock"] as? Bool == true })
let weatherItems = json.filter { $0["type"] as? String == "weather" }
precondition(weatherItems.count == 1, "one weather placeholder in the default preset")
precondition(weatherItems[0]["api_key"] == nil, "default preset must not contain an API key")
precondition(weatherItems[0]["width"] as? Int == 80, "preserve weather control width")
precondition(!json.contains { ["previous", "next"].contains($0["type"] as? String ?? "") }, "skip controls must not use HID")
for direction in ["previous", "next"] {
    let expected = "~/Library/Application Support/MTMR/ManagedMedia/v1/SpotifyArtwork/" + direction
    let controls = json.filter { item in
        item["type"] as? String == "staticButton" &&
        (item["image"] as? [String:Any])?["filePath"] as? String == expected + ".png" &&
        (item["actionAppleScript"] as? [String:Any])?["filePath"] as? String == expected + ".applescript"
    }
    precondition(controls.count == 1, "one managed Spotify skip control per direction")
    let script = try String(contentsOf: resources.appendingPathComponent("ManagedMedia/v1/SpotifyArtwork/" + direction + ".applescript"), encoding: .utf8)
    precondition(script.contains("if application id \"com.spotify.client\" is running"))
    precondition(script.contains("to " + direction + " track"))
}
let sourcePaths=json.compactMap { ($0["source"] as? [String:Any])?["filePath"] as? String }
precondition(sourcePaths.count == 4)
precondition(sourcePaths.allSatisfy { $0.hasPrefix("~/Library/Application Support/MTMR/ManagedMedia/v1/") })
print("Managed media bundle and preservation tests passed")
