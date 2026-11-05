import Foundation
import CoreFoundation

struct WeatherReading: Equatable {
    let temperature: Int
    let icon: String?
}

enum WeatherLocationSelection: Equatable {
    case currentLocation
    case city(name: String, latitude: Double, longitude: Double)
}

enum WeatherLocationSettings {
    static let changed = Notification.Name("MTMRWeatherLocationChanged")
    private static let key = "weatherLocationSelection"

    static var selection: WeatherLocationSelection { read(from: .standard) }

    static func read(from defaults: UserDefaults) -> WeatherLocationSelection {
        guard let value = defaults.dictionary(forKey: key), value["mode"] as? String == "city",
              let name = value["name"] as? String, !name.isEmpty,
              let latitude = value["latitude"] as? Double, latitude.isFinite, (-90...90).contains(latitude),
              let longitude = value["longitude"] as? Double, longitude.isFinite, (-180...180).contains(longitude)
        else { return .currentLocation }
        return .city(name: name, latitude: latitude, longitude: longitude)
    }

    static func useCurrentLocation(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static func useCity(name: String, latitude: Double, longitude: Double, defaults: UserDefaults = .standard) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, latitude.isFinite, (-90...90).contains(latitude),
              longitude.isFinite, (-180...180).contains(longitude) else { return }
        defaults.set(["mode": "city", "name": name, "latitude": latitude, "longitude": longitude], forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }
}

enum WeatherResponse {
    /// Construct an HTTPS request using escaped parameters, never forced URLs.
    static func requestURL(latitude: Double, longitude: Double, units: String, apiKey: String) -> URL? {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard latitude.isFinite, (-90...90).contains(latitude), longitude.isFinite,
              (-180...180).contains(longitude), !key.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.openweathermap.org"
        components.path = "/data/2.5/weather"
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "units", value: units),
            URLQueryItem(name: "appid", value: key)
        ]
        return components.url
    }

    /// A missing icon is acceptable; an invalid response or temperature isn't.
    static func parse(statusCode: Int?, data: Data?) -> WeatherReading? {
        guard let statusCode = statusCode, (200..<300).contains(statusCode),
              let data = data, !data.isEmpty, data.count <= 1_000_000,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let main = json["main"] as? [String: Any],
              let number = main["temp"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let temperature = number.doubleValue
        guard temperature.isFinite, let integer = Int(exactly: temperature.rounded(.towardZero)) else { return nil }
        let icon = (json["weather"] as? [[String: Any]])?.first?["icon"] as? String
        return WeatherReading(temperature: integer, icon: icon)
    }
}
