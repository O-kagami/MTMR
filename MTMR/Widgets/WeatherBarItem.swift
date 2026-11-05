//
//  WeatherBarItem.swift
//  MTMR
//
//  Created by Daniel Apatin on 18.04.2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa
import CoreLocation

class WeatherBarItem: CustomButtonTouchBarItem, CLLocationManagerDelegate {
    private let activity: NSBackgroundActivityScheduler
    private var units: String
    private var api_key: String
    private var units_str = "°F"
    private var location: CLLocation?
    private var request: URLSessionDataTask?
    private var requestGeneration = 0
    private let iconsImages = ["01d": "☀️", "01n": "☀️", "02d": "⛅️", "02n": "⛅️", "03d": "☁️", "03n": "☁️", "04d": "☁️", "04n": "☁️", "09d": "⛅️", "09n": "⛅️", "10d": "🌦", "10n": "🌦", "11d": "🌩", "11n": "🌩", "13d": "❄️", "13n": "❄️", "50d": "🌫", "50n": "🌫"]
    private let iconsText = ["01d": "☀", "01n": "☀", "02d": "☁", "02n": "☁", "03d": "☁", "03n": "☁", "04d": "☁", "04n": "☁", "09d": "☂", "09n": "☂", "10d": "☂", "10n": "☂", "11d": "☈", "11n": "☈", "13d": "☃", "13n": "☃", "50d": "♨", "50n": "♨"]
    private var iconsSource: Dictionary<String, String>

    private var manager: CLLocationManager?

    init(identifier: NSTouchBarItem.Identifier, interval: TimeInterval, units: String, api_key: String, icon_type: String? = "text") {
        activity = NSBackgroundActivityScheduler(identifier: "\(identifier.rawValue).updatecheck")
        activity.interval = interval
        self.units = units
        self.api_key = api_key

        if self.units == "metric" {
            units_str = "°C"
        }

        if self.units == "imperial" {
            units_str = "°F"
        }

        if icon_type == "images" {
            iconsSource = iconsImages
        } else {
            iconsSource = iconsText
        }

        super.init(identifier: identifier, title: "⏳")

        // Do not request location or contact the weather service without a user-supplied key.
        guard !api_key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            title = "天気:要設定"
            return
        }

        activity.repeats = true
        activity.qualityOfService = .utility
        activity.schedule { [weak self] (completion: NSBackgroundActivityScheduler.CompletionHandler) in
            self?.updateWeather()
            completion(NSBackgroundActivityScheduler.Result.finished)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(locationSelectionChanged), name: WeatherLocationSettings.changed, object: nil)
        locationSelectionChanged()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func updateWeather() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.updateWeather() }
            return
        }
        guard let location = location,
              let url = WeatherResponse.requestURL(latitude: location.coordinate.latitude,
                                                   longitude: location.coordinate.longitude,
                                                   units: units, apiKey: api_key) else { return }
        request?.cancel()
        requestGeneration += 1
        let generation = requestGeneration
        request = URLSession.shared.dataTask(with: URLRequest(url: url)) { [weak self] data, response, error in
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.requestGeneration == generation else { return }
                guard error == nil, let reading = WeatherResponse.parse(statusCode: (response as? HTTPURLResponse)?.statusCode, data: data) else {
                    self.setWeather(text: "天気:取得不可")
                    return
                }
                let icon = reading.icon.flatMap { self.iconsSource[$0] } ?? ""
                self.setWeather(text: icon.isEmpty ? "\(reading.temperature)\(self.units_str)" : "\(icon) \(reading.temperature)\(self.units_str)")
            }
        }
        request?.resume()
    }

    @objc private func locationSelectionChanged() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.locationSelectionChanged() }
            return
        }
        requestGeneration += 1
        request?.cancel()
        request = nil
        manager?.stopUpdatingLocation()
        manager?.delegate = nil
        manager = nil
        location = nil
        title = "⏳"
        switch WeatherLocationSettings.selection {
        case let .city(_, latitude, longitude):
            location = CLLocation(latitude: latitude, longitude: longitude)
            updateWeather()
        case .currentLocation:
            let manager = CLLocationManager()
            self.manager = manager
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyKilometer
            manager.distanceFilter = 1000
            let status = CLLocationManager.authorizationStatus()
            if status == .denied || status == .restricted {
                title = "位置情報:許可必要"
            } else {
                if status == .notDetermined { manager.requestWhenInUseAuthorization() }
                manager.startUpdatingLocation()
            }
        }
    }

    func setWeather(text: String) {
        title = text
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manager === self.manager, let lastLocation = locations.last else { return }
        location = lastLocation
        updateWeather()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard manager === self.manager else { return }
        print(error)
        if location == nil { title = "位置情報:取得不可" }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        guard manager === self.manager else { return }
        if status == .denied || status == .restricted {
            manager.stopUpdatingLocation()
            location = nil
            requestGeneration += 1
            request?.cancel()
            title = "位置情報:許可必要"
        } else if status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        request?.cancel()
        manager?.stopUpdatingLocation()
        activity.invalidate()
    }
}
