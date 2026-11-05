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
    private var prev_location: CLLocation!
    private var location: CLLocation!
    private let iconsImages = ["01d": "☀️", "01n": "☀️", "02d": "⛅️", "02n": "⛅️", "03d": "☁️", "03n": "☁️", "04d": "☁️", "04n": "☁️", "09d": "⛅️", "09n": "⛅️", "10d": "🌦", "10n": "🌦", "11d": "🌩", "11n": "🌩", "13d": "❄️", "13n": "❄️", "50d": "🌫", "50n": "🌫"]
    private let iconsText = ["01d": "☀", "01n": "☀", "02d": "☁", "02n": "☁", "03d": "☁", "03n": "☁", "04d": "☁", "04n": "☁", "09d": "☂", "09n": "☂", "10d": "☂", "10n": "☂", "11d": "☈", "11n": "☈", "13d": "☃", "13n": "☃", "50d": "♨", "50n": "♨"]
    private var iconsSource: Dictionary<String, String>

    private var manager: CLLocationManager!

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

        let status = CLLocationManager.authorizationStatus()
        if status == .restricted || status == .denied {
            print("User permission not given")
            return
        }

        if !CLLocationManager.locationServicesEnabled() {
            print("Location services not enabled")
            return
        }

        activity.repeats = true
        activity.qualityOfService = .utility
        activity.schedule { (completion: NSBackgroundActivityScheduler.CompletionHandler) in
            self.updateWeather()
            completion(NSBackgroundActivityScheduler.Result.finished)
        }
        updateWeather()

        manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.startUpdatingLocation()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func updateWeather() {
        guard let location = location,
              let url = WeatherResponse.requestURL(latitude: location.coordinate.latitude,
                                                   longitude: location.coordinate.longitude,
                                                   units: units, apiKey: api_key) else { return }
        let task = URLSession.shared.dataTask(with: URLRequest(url: url)) { [weak self] data, response, error in
            guard error == nil,
                  let reading = WeatherResponse.parse(statusCode: (response as? HTTPURLResponse)?.statusCode, data: data),
                  let self = self else { return }
            let icon = reading.icon.flatMap { self.iconsSource[$0] } ?? ""
            let text = icon.isEmpty ? "\(reading.temperature)\(self.units_str)" : "\(icon) \(reading.temperature)\(self.units_str)"
            DispatchQueue.main.async { [weak self] in self?.setWeather(text: text) }
        }
        task.resume()
    }

    func setWeather(text: String) {
        title = text
    }

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let lastLocation = locations.last else { return }
        location = lastLocation
        if prev_location == nil {
            updateWeather()
        }
        prev_location = lastLocation
    }

    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        print(error)
    }

    func locationManager(_: CLLocationManager, didChangeAuthorization _: CLAuthorizationStatus) {
//        print("inside didChangeAuthorization ");
        updateWeather()
    }
    
    deinit {
        activity.invalidate()
    }
}
