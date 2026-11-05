import AppKit
import CoreLocation

/// A retained controller is needed because the status menu is rebuilt whenever
/// the foreground application changes. Geocoding does not require location access.
final class WeatherLocationMenu: NSObject {
    private struct City {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    private let geocoder = CLGeocoder()
    private var searchGeneration = 0
    private var cities: [City] = []
    private var window: NSWindow?
    private var searchField: NSTextField!
    private var results: NSPopUpButton!
    private var applyButton: NSButton!
    private var message: NSTextField!
    private var selectedLocation: NSTextField!

    func makeItem() -> NSMenuItem {
        let item = NSMenuItem(title: "天気の場所…", action: #selector(open(_:)), keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func open(_ sender: Any?) {
        if window == nil { createWindow() }
        switch WeatherLocationSettings.selection {
        case .currentLocation:
            selectedLocation.stringValue = "現在の設定：現在地"
        case let .city(name, _, _):
            selectedLocation.stringValue = "現在の設定：\(name)"
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(searchField)
    }

    private func createWindow() {
        let width: CGFloat = 460
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 210),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "天気の場所"
        panel.isReleasedWhenClosed = false
        panel.center()
        guard let content = panel.contentView else { return }

        selectedLocation = NSTextField(labelWithString: "")
        selectedLocation.frame = NSRect(x: 20, y: 177, width: 420, height: 19)
        selectedLocation.lineBreakMode = .byTruncatingTail
        content.addSubview(selectedLocation)

        searchField = NSTextField(frame: NSRect(x: 20, y: 139, width: 325, height: 24))
        searchField.placeholderString = "都市名を入力（例：札幌、Tokyo）"
        searchField.target = self
        searchField.action = #selector(search(_:))
        content.addSubview(searchField)
        let searchButton = NSButton(title: "検索", target: self, action: #selector(search(_:)))
        searchButton.frame = NSRect(x: 352, y: 135, width: 88, height: 32)
        content.addSubview(searchButton)

        results = NSPopUpButton(frame: NSRect(x: 20, y: 99, width: 325, height: 28), pullsDown: false)
        results.isEnabled = false
        content.addSubview(results)
        applyButton = NSButton(title: "設定", target: self, action: #selector(applyCity(_:)))
        applyButton.frame = NSRect(x: 352, y: 97, width: 88, height: 32)
        applyButton.isEnabled = false
        content.addSubview(applyButton)

        message = NSTextField(labelWithString: "都市を検索して候補から選択してください。")
        message.textColor = .secondaryLabelColor
        message.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        message.frame = NSRect(x: 20, y: 72, width: 420, height: 18)
        message.lineBreakMode = .byTruncatingTail
        content.addSubview(message)

        let currentButton = NSButton(title: "現在地を使用", target: self, action: #selector(useCurrentLocation(_:)))
        currentButton.frame = NSRect(x: 20, y: 21, width: 145, height: 32)
        content.addSubview(currentButton)
        window = panel
    }

    @objc private func search(_ sender: Any?) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        searchGeneration += 1
        let generation = searchGeneration
        geocoder.cancelGeocode()
        cities = []
        results.removeAllItems()
        results.isEnabled = false
        applyButton.isEnabled = false
        guard !query.isEmpty else {
            message.stringValue = "都市名を入力してください。"
            return
        }
        message.stringValue = "検索中…"
        geocoder.geocodeAddressString(query) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                guard let self = self, self.searchGeneration == generation else { return }
                guard error == nil else {
                    self.message.stringValue = "検索できませんでした。通信環境や都市名を確認してください。"
                    return
                }
                var seen = Set<String>()
                self.cities = (placemarks ?? []).compactMap { place in
                    guard let location = place.location,
                          CLLocationCoordinate2DIsValid(location.coordinate) else { return nil }
                    let components = [place.locality ?? place.name, place.administrativeArea, place.country]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    var unique: [String] = []
                    for part in components where !unique.contains(part) { unique.append(part) }
                    guard !unique.isEmpty else { return nil }
                    let name = unique.joined(separator: "、")
                    let lat = location.coordinate.latitude
                    let lon = location.coordinate.longitude
                    let key = "\(name)|\(lat)|\(lon)"
                    guard seen.insert(key).inserted else { return nil }
                    return City(name: name, latitude: lat, longitude: lon)
                }
                guard !self.cities.isEmpty else {
                    self.message.stringValue = "候補が見つかりませんでした。別の名前で検索してください。"
                    return
                }
                self.results.addItems(withTitles: self.cities.map { $0.name })
                self.results.isEnabled = true
                self.applyButton.isEnabled = true
                self.message.stringValue = "候補を選び、「設定」を押してください。"
            }
        }
    }

    @objc private func applyCity(_ sender: Any?) {
        let index = results.indexOfSelectedItem
        guard cities.indices.contains(index) else { return }
        let city = cities[index]
        WeatherLocationSettings.useCity(name: city.name, latitude: city.latitude, longitude: city.longitude)
        window?.close()
    }

    @objc private func useCurrentLocation(_ sender: Any?) {
        WeatherLocationSettings.useCurrentLocation()
        window?.close()
    }
}
