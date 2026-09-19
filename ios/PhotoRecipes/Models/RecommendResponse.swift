import Foundation

struct RecommendResponse: Codable, Hashable {
    var presetId: String?
    var reason: String?
    var tips: [String]?
    var preset: Recipe?
    var model: String?
    var vision: Bool?
    var error: String?
    var code: String?
}

struct RecommendRequest: Encodable {
    var message: String
    var favorites: [String]
    var image: String?
}
