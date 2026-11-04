import Foundation
protocol SourceProtocol { var string: String? { get } }
struct Source: SourceProtocol { let filePath: String?; let string: String? }
