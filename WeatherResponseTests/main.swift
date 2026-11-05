import Foundation
func data(_ text: String) -> Data { Data(text.utf8) }
func parse(_ text: String, _ status: Int? = 200) -> WeatherReading? { WeatherResponse.parse(statusCode: status, data: data(text)) }
let good = "{\"main\":{\"temp\":21.8},\"weather\":[{\"icon\":\"01d\"}]}"
precondition(parse(good) == WeatherReading(temperature: 21, icon: "01d"))
precondition(parse("{\"main\":{\"temp\":-3.9},\"weather\":[]}") == WeatherReading(temperature: -3, icon: nil), "empty weather array is safe")
precondition(parse("{\"main\":{\"temp\":10},\"weather\":[{}]}") == WeatherReading(temperature: 10, icon: nil), "missing icon is safe")
precondition(parse("{\"main\":{\"temp\":10},\"weather\":[{\"icon\":3}]}") == WeatherReading(temperature: 10, icon: nil), "invalid icon is safe")
precondition(parse("{\"main\":{\"temp\":10}}") == WeatherReading(temperature: 10, icon: nil), "missing weather is safe")
precondition(parse(good, 401) == nil && parse(good, 500) == nil && parse(good, nil) == nil, "non-success HTTP must be rejected")
precondition(WeatherResponse.parse(statusCode: 200, data: nil) == nil)
precondition(WeatherResponse.parse(statusCode: 200, data: Data()) == nil)
precondition(parse("{") == nil && parse("[]") == nil && parse("{}") == nil)
precondition(parse("{\"main\":{\"temp\":true}}") == nil, "boolean isn't a temperature")
precondition(parse("{\"main\":{\"temp\":\"cold\"}}") == nil)
precondition(parse("{\"main\":{\"temp\":1e100}}") == nil, "out-of-range integer must not trap")
precondition(WeatherResponse.parse(statusCode: 200, data: Data(repeating: 32, count: 1_000_001)) == nil)
precondition(WeatherResponse.requestURL(latitude: .nan, longitude: 0, units: "metric", apiKey: "test") == nil)
precondition(WeatherResponse.requestURL(latitude: 91, longitude: 0, units: "metric", apiKey: "test") == nil)
precondition(WeatherResponse.requestURL(latitude: 0, longitude: 181, units: "metric", apiKey: "test") == nil)
precondition(WeatherResponse.requestURL(latitude: 0, longitude: 0, units: "metric", apiKey: "  ") == nil)
let url = WeatherResponse.requestURL(latitude: 0, longitude: 0, units: "metric", apiKey: "a&b=1")!
precondition(url.scheme == "https" && url.host == "api.openweathermap.org")
precondition(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "appid" }?.value == "a&b=1", "key must be a single escaped parameter")
print("Weather response and URL safety tests passed")
